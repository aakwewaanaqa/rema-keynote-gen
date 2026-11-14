import Foundation
import libxml2

// 系統內建 libxml2 的 HTML parser 薄包裝——原本 Ruby 版用的 Nokogiri 底層也是 libxml2，
// 所以容錯行為（亂七八糟的 HTML 照樣解析）跟以前一致。選取節點用 XPath（libxml2 沒有 CSS selector）。
// 網頁編碼（信望愛是 Big5、holybible.or.kr 是 EUC-KR）直接交給 libxml2 轉，不用先自己轉成 UTF-8。
final class HTMLDocument {
    fileprivate let doc: htmlDocPtr
    // remove() 拆下來的節點不在樹上，xmlFreeDoc 不會管，等 document 釋放時一起 free
    fileprivate var detached: [xmlNodePtr] = []

    init?(data: Data, encoding: String) {
        let options = Int32(
            HTML_PARSE_RECOVER.rawValue | HTML_PARSE_NOERROR.rawValue
                | HTML_PARSE_NOWARNING.rawValue | HTML_PARSE_NONET.rawValue)
        let parsed: htmlDocPtr? = data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return nil }
            return htmlReadMemory(base.assumingMemoryBound(to: CChar.self), Int32(buffer.count), nil, encoding, options)
        }
        guard let parsed else { return nil }
        doc = parsed
    }

    deinit {
        detached.forEach { xmlFreeNode($0) }
        xmlFreeDoc(doc)
    }

    func nodes(_ xpath: String) -> [HTMLNode] {
        evaluate(xpath, from: nil)
    }

    fileprivate func evaluate(_ xpath: String, from node: xmlNodePtr?) -> [HTMLNode] {
        guard let context = xmlXPathNewContext(doc) else { return [] }
        defer { xmlXPathFreeContext(context) }
        if let node { context.pointee.node = node }

        guard let result = xmlXPathEvalExpression(xpath, context) else { return [] }
        defer { xmlXPathFreeObject(result) }
        guard let set = result.pointee.nodesetval, let tab = set.pointee.nodeTab else { return [] }
        return (0..<Int(set.pointee.nodeNr)).compactMap { i in
            tab[i].map { HTMLNode(document: self, node: $0) }
        }
    }
}

// 持有 document 的參考，確保節點存活期間 document 不會先被釋放
struct HTMLNode {
    let document: HTMLDocument
    let node: xmlNodePtr

    // 所有子孫文字節點串起來，等同 Nokogiri 的 node.text
    var text: String {
        guard let content = xmlNodeGetContent(node) else { return "" }
        defer { xmlFree(content) }
        return String(cString: content)
    }

    func attribute(_ name: String) -> String? {
        guard let value = xmlGetProp(node, name) else { return nil }
        defer { xmlFree(value) }
        return String(cString: value)
    }

    // 相對於這個節點的 XPath（記得用 "." 開頭，例如 ".//li"）
    func nodes(_ xpath: String) -> [HTMLNode] {
        document.evaluate(xpath, from: node)
    }

    // 從樹上拿掉，等同 Nokogiri 的 node.remove。
    // 不能當場 xmlFreeNode：XPath 結果常有巢狀節點（例如 h3 裡的 sup.footnote），
    // 先 free 外層會連子樹一起釋放，輪到內層時就 double free。
    // 改成只 unlink、交給 document 在 deinit 時釋放；內層節點會先從外層拆出來，所以每個節點只 free 一次。
    func remove() {
        guard !document.detached.contains(node) else { return }
        xmlUnlinkNode(node)
        document.detached.append(node)
    }
}

// XPath 1.0 沒有「class 含有某個值」的語法，這是標準寫法，等同 CSS 的 .name
func xpathHasClass(_ name: String) -> String {
    "contains(concat(' ', normalize-space(@class), ' '), ' \(name) ')"
}

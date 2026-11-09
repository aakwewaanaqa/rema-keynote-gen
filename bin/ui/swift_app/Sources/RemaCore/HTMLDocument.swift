import Foundation
import libxml2

// 系統內建 libxml2 的 HTML parser 薄包裝——原本 Ruby 版用的 Nokogiri 底層也是 libxml2，
// 所以容錯行為（亂七八糟的 HTML 照樣解析）跟以前一致。選取節點用 XPath（libxml2 沒有 CSS selector）。
// 網頁編碼（信望愛是 Big5、holybible.or.kr 是 EUC-KR）直接交給 libxml2 轉，不用先自己轉成 UTF-8。
final class HTMLDocument {
    fileprivate let doc: htmlDocPtr

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

    // 從樹上拿掉並釋放，等同 Nokogiri 的 node.remove。呼叫後這個 HTMLNode 不能再使用
    func remove() {
        xmlUnlinkNode(node)
        xmlFreeNode(node)
    }
}

// XPath 1.0 沒有「class 含有某個值」的語法，這是標準寫法，等同 CSS 的 .name
func xpathHasClass(_ name: String) -> String {
    "contains(concat(' ', normalize-space(@class), ' '), ' \(name) ')"
}

import XCTest
@testable import RemaCore

final class HTMLDocumentTests: XCTestCase {
    // BibleGateway 的標題 h3 裡會夾 sup.footnote，同一次 XPath 會同時選到外層跟內層。
    // 以前 remove() 當場 xmlFreeNode，先 free h3 再 free 裡面的 sup 就 double free 閃退
    func testRemoveNestedNodes() throws {
        let html = #"<div class="passage-text"><h3>Title<sup class="footnote">a</sup></h3><span class="text">Body</span></div>"#
        let doc = try XCTUnwrap(HTMLDocument(data: Data(html.utf8), encoding: "UTF-8"))
        let container = try XCTUnwrap(doc.nodes("//div").first)

        let noise = container.nodes(".//h3 | .//sup[\(xpathHasClass("footnote"))]")
        XCTAssertEqual(noise.count, 2)
        noise.forEach { $0.remove() }
        noise.forEach { $0.remove() }

        XCTAssertEqual(container.text, "Body")
    }
}

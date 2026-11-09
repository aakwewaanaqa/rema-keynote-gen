import XCTest
@testable import RemaCore

// 對照原本的 tests/test_bible_template.rb
final class BibleTemplateTests: XCTestCase {
    private let entry = BibleQueryEntry(
        book: "Acts", chapter: 6, verse: 1,
        texts: ["麥可陳內容", "信望愛內容", "NIV content", "gae content", "NKJV content", "KJV content"]
    )

    private func render(_ body: String, errors: inout [String]) -> String {
        BibleTemplate.renderPlaceholder(body, entry: entry, errors: &errors, placeholderName: "p")
    }

    func testAliasTokensResolveToSameValueAsCanonicalToken() {
        var errors: [String] = []
        XCTAssertEqual(render("{中} / {cuv}", errors: &errors), "信望愛內容 / 信望愛內容")
        XCTAssertEqual(errors, [])
    }

    func testComputedTokenAliases() {
        var errors: [String] = []
        XCTAssertEqual(
            render("{中書}/{cb} {英書}/{eb} {韓書}/{kb} {章}/{ch} {節}/{vr}", errors: &errors),
            "使徒行傳/使徒行傳 Acts/Acts 사도행전/사도행전 6/6 1/1"
        )
        XCTAssertEqual(errors, [])
    }

    func testKjvSourceToken() {
        var errors: [String] = []
        XCTAssertEqual(render("{kjv}", errors: &errors), "KJV content")
        XCTAssertEqual(errors, [])
    }

    func testSourceAliasTokens() {
        var errors: [String] = []
        XCTAssertEqual(render("{英} {韓} {英王} {新英王}", errors: &errors), "NIV content gae content KJV content NKJV content")
        XCTAssertEqual(errors, [])
    }

    func testLocalToken() {
        var errors: [String] = []
        XCTAssertEqual(render("{local}", errors: &errors), "麥可陳內容")
    }

    func testUnknownTokenReportsOriginalAliasText() {
        var errors: [String] = []
        XCTAssertEqual(render("{不存在}", errors: &errors), "⚠️{不存在}")
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("未知的 token {不存在}"))
        XCTAssertTrue(errors[0].hasPrefix("使徒行傳6:1 #p"))
    }

    func testMissingSourceTextIsReported() {
        let sparse = BibleQueryEntry(book: "Acts", chapter: 6, verse: 1, texts: ["", "信望愛內容", "", "", "", ""])
        var errors: [String] = []
        let rendered = BibleTemplate.renderPlaceholder("{英}", entry: sparse, errors: &errors, placeholderName: "en")
        XCTAssertEqual(rendered, "⚠️{英}")
        XCTAssertTrue(errors[0].contains("來源 {英} 沒有經文"))
    }

    func testLiteralBackslashNBecomesNewline() {
        var errors: [String] = []
        XCTAssertEqual(render("{章}\\n{節}", errors: &errors), "6\n1")
    }

    func testCanonicalTokenPassesThroughUnknownNames() {
        XCTAssertEqual(BibleTemplate.canonicalToken("niv"), "niv")
        XCTAssertEqual(BibleTemplate.canonicalToken("中"), "fhl")
        XCTAssertEqual(BibleTemplate.canonicalToken("英"), "niv")
        XCTAssertEqual(BibleTemplate.canonicalToken("英王"), "kjv")
        XCTAssertEqual(BibleTemplate.canonicalToken("新英王"), "nkjv")
        XCTAssertEqual(BibleTemplate.canonicalToken("not_a_token"), "not_a_token")
    }
}

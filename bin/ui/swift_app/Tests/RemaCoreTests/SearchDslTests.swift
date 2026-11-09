import XCTest
@testable import RemaCore

// 對照原本的 tests/test_seach_dsl.rb
final class SearchDslTokenizeTests: XCTestCase {
    func testIdentifier() {
        let tokens = SearchDsl.tokenize("馬太福音")
        XCTAssertEqual(tokens.map(\.kind), [.identifier])
    }

    func testTokenTypes() {
        let tokens = SearchDsl.tokenize("馬太福音3:4,5～7；彼得前書1:7")
        XCTAssertEqual(tokens.map(\.kind), [
            .identifier, .number, .colon, .number, .comma, .number, .hyphen, .number,
            .semicolon, .identifier, .number, .colon, .number,
        ])
    }

    func testLineBreakBecomesSingleSemicolon() {
        let tokens = SearchDsl.tokenize("創1:1 \n\n  出2:3")
        XCTAssertEqual(tokens.filter { $0.kind == .semicolon }.count, 1)
    }
}

final class SearchDslParseTests: XCTestCase {
    private func parse(_ str: String) -> SearchDsl.Query { SearchDsl.parse(str) }

    func testWholeChapter() {
        let ref = parse("創1").refs[0]
        XCTAssertEqual(ref.book, "Genesis")
        XCTAssertEqual(ref.chapter, 1)
        XCTAssertNil(ref.verses)
    }

    func testSingleVerse() {
        XCTAssertEqual(parse("創1:1").refs, [.init(book: "Genesis", chapter: 1, verses: [.single(1)])])
    }

    func testVerseRange() {
        XCTAssertEqual(parse("創1:1-5").refs[0].verses, [.range(1, 5)])
    }

    func testOpenEndedRange() {
        XCTAssertEqual(parse("創1:3-").refs[0].verses, [.range(3, nil)])
    }

    func testMixedVerseList() {
        let ref = parse("太1:1-5,7,8,10-12").refs[0]
        XCTAssertEqual(ref.book, "Matthew")
        XCTAssertEqual(ref.verses, [.range(1, 5), .single(7), .single(8), .range(10, 12)])
    }

    func testMultipleRefsWithSemicolon() {
        let refs = parse("太1:1-5,7,8,10-12;創3:7").refs
        XCTAssertEqual(refs, [
            .init(book: "Matthew", chapter: 1, verses: [.range(1, 5), .single(7), .single(8), .range(10, 12)]),
            .init(book: "Genesis", chapter: 3, verses: [.single(7)]),
        ])
    }

    func testChineseFullName() {
        XCTAssertEqual(parse("馬太福音3:4,5～7；彼得前書1:7").refs, [
            .init(book: "Matthew", chapter: 3, verses: [.single(4), .range(5, 7)]),
            .init(book: "1Peter", chapter: 1, verses: [.single(7)]),
        ])
    }

    func testEnglishAcronym() {
        XCTAssertEqual(parse("Matt3:16").refs, [.init(book: "Matthew", chapter: 3, verses: [.single(16)])])
    }

    func testUnknownBookReturnsEmpty() {
        XCTAssertEqual(parse("不存在書9:1").refs, [])
    }

    func testChapterSwitchWithComma() {
        XCTAssertEqual(parse("創2:15,3:6").refs, [
            .init(book: "Genesis", chapter: 2, verses: [.single(15)]),
            .init(book: "Genesis", chapter: 3, verses: [.single(6)]),
        ])
    }

    func testChapterSwitchWithIdeographicComma() {
        XCTAssertEqual(parse("創世記2:15、3:6").refs.map(\.chapter), [2, 3])
    }

    func testSameChapterCommaIsNotMistakenForChapterSwitch() {
        let refs = parse("太1:1-5,7").refs
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs[0].verses, [.range(1, 5), .single(7)])
    }

    func testNewlineSeparatedRefsWithoutSemicolon() {
        let refs = parse("啟示錄3:7-8\n使徒行傳5:19\n約翰福音10:7\n路加福音 19:3-5\n林前16:5-9").refs
        XCTAssertEqual(refs.map(\.book), ["Revelation", "Acts", "John", "Luke", "1Corinthians"])
        XCTAssertEqual(refs.map(\.chapter), [3, 5, 10, 19, 16])
    }

    func testCrlfLineBreaks() {
        XCTAssertEqual(parse("創1:1\r\n出2:3").refs.map(\.book), ["Genesis", "Exodus"])
    }
}

final class BibleTests: XCTestCase {
    func testMatchByVariousNames() {
        XCTAssertEqual(Bible.match("Genesis")?.code, "Genesis")
        XCTAssertEqual(Bible.match("創世記")?.code, "Genesis")
        XCTAssertEqual(Bible.match("林前")?.code, "1Corinthians")
        XCTAssertEqual(Bible.match("psalm")?.code, "Psalm")
        XCTAssertEqual(Bible.match("Revelaton")?.code, "Revelation")  // 編輯距離 1
        XCTAssertNil(Bible.match("不存在書"))
    }

    func testPureChapterIndex() {
        XCTAssertEqual(Bible.pureChapterIndex(code: "Genesis", chapter: 1), 1)
        XCTAssertEqual(Bible.pureChapterIndex(code: "Exodus", chapter: 1), 51)
        XCTAssertEqual(Bible.pureChapterIndex(code: "Revelation", chapter: 22), 1189)
    }
}

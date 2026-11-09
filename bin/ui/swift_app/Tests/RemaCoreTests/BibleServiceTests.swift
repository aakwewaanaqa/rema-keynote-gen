import XCTest
@testable import RemaCore

// 讀本機 bible_src，對照原本 tests/test_seach_dsl.rb 的 TestGithubMichaelChanBibleQuery。
// 沒 clone bible_src 的機器直接略過
final class LocalBibleServiceTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: RemaPaths.bibleSource.path),
                          "找不到 \(RemaPaths.bibleSource.path)，略過")
    }

    private func query(_ str: String, translation: String = "cuv2") async throws -> [BibleVerse] {
        try await LocalBibleService(translation: translation).query(SearchDsl.parse(str))
    }

    func testSingleVerse() async throws {
        let results = try await query("創1:1")
        XCTAssertEqual(results, [BibleVerse(book: "Genesis", chapter: 1, verse: 1, text: "起初，神創造天地。")])
    }

    func testVerseRange() async throws {
        let results = try await query("創1:1-3")
        XCTAssertEqual(results.map(\.verse), [1, 2, 3])
    }

    func testMixedVerseList() async throws {
        let results = try await query("太5:3,5")
        XCTAssertEqual(results.map(\.verse), [3, 5])
    }

    func testWholeChapter() async throws {
        let results = try await query("約3")
        XCTAssertGreaterThan(results.count, 1)
        XCTAssertTrue(results.allSatisfy { $0.chapter == 3 })
    }

    func testMultipleBooks() async throws {
        let results = try await query("太5:3;約3:16")
        XCTAssertEqual(results.map { [$0.chapter, $0.verse] }, [[5, 3], [3, 16]])
    }

    func testUnknownBookReturnsEmpty() async throws {
        let results = try await query("不存在書9:1")
        XCTAssertEqual(results, [])
    }

    func testTranslationKjv() async throws {
        let results = try await query("Gen1:1", translation: "kjv")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].text.lowercased().contains("beginning"))
    }

    func testMissingSourceDirectoryThrows() async {
        let service = LocalBibleService(sourceDirectory: URL(fileURLWithPath: "/nonexistent/bible_src"))
        do {
            _ = try await service.query(SearchDsl.parse("創1:1"))
            XCTFail("應該要丟出錯誤")
        } catch {}
    }
}

// 對照原本的 tests/test_advanced_bible_query_cli.rb：守住給 App 預覽用的查詢結果結構
final class BibleVerseQueryTests: XCTestCase {
    func testEmptySearchTextThrows() async {
        do {
            _ = try await BibleVerseQuery.run("", sources: [.local])
            XCTFail("應該要丟出錯誤")
        } catch {}
    }

    func testNoSourceEnabledReturnsStatusWithoutVerses() async throws {
        let outcome = try await BibleVerseQuery.run("創1:1", sources: [])
        XCTAssertEqual(outcome.verses, [])
        XCTAssertFalse(outcome.status.isEmpty)
    }

    func testLocalSourceReturnsStructuredVerses() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: RemaPaths.bibleSource.path))
        let outcome = try await BibleVerseQuery.run("創1:1-3", sources: [.local])
        XCTAssertEqual(outcome.verses.map(\.verse), [1, 2, 3])
        XCTAssertEqual(outcome.verses[0].translations, [
            VerseTranslation(service: "local", translation: "麥可陳", book: "創世記", content: "起初，神創造天地。"),
        ])
    }

    // 書卷名要跟著譯本語言變：同一節底下兩個譯本共用同一個 chapter/verse，但各自的 book 不同
    func testBookNameFollowsTranslationLanguage() {
        let entry = BibleQueryEntry(book: "Acts", chapter: 6, verse: 1, texts: ["", "中文", "English", "한국어", "", ""])
        let groups = BibleVerseQuery.groups(from: [entry])
        XCTAssertEqual(groups[0].translations.map(\.book), ["使徒行傳", "Acts", "사도행전"])
        XCTAssertEqual(groups[0].translations.map(\.service), ["fhl", "niv", "gae"])
    }

    // 個別來源掛掉不能讓其他來源一起查不到
    func testFailingSourceIsReportedSeparately() async throws {
        struct Broken: BibleService {
            let name = "Broken"
            func query(_ query: SearchDsl.Query) async throws -> [BibleVerse] { throw RemaError("原站故障") }
        }
        struct Fixed: BibleService {
            let name = "Fixed"
            func query(_ query: SearchDsl.Query) async throws -> [BibleVerse] {
                [BibleVerse(book: "Genesis", chapter: 1, verse: 1, text: "ok")]
            }
        }
        let outcome = try await BibleQuery.run("創1:1", sources: [(true, Broken()), (true, Fixed()), (false, Broken())])
        XCTAssertEqual(outcome.entries, [BibleQueryEntry(book: "Genesis", chapter: 1, verse: 1, texts: ["", "ok", ""])])
        XCTAssertEqual(outcome.sourceErrors, ["Broken: 原站故障"])
    }

    // 勾 CUV＋NIV 時，經文要各自落在自己來源的那一格，不能全擠到第 0 格（麥可陳）。
    // 這個錯只在 release 編譯出現，要用 swift test -c release -Xswiftc -enable-testing 才驗得到
    func testEachSourceKeepsItsOwnIndex() async throws {
        struct Fixed: BibleService {
            let name: String
            let text: String
            func query(_ query: SearchDsl.Query) async throws -> [BibleVerse] {
                [BibleVerse(book: "Acts", chapter: 24, verse: 10, text: text)]
            }
        }
        let outcome = try await BibleQuery.run("徒24:10", sources: [
            (false, Fixed(name: "local", text: "麥可陳")),
            (true, Fixed(name: "fhl", text: "中文")),
            (true, Fixed(name: "niv", text: "English")),
        ])
        XCTAssertEqual(outcome.entries, [BibleQueryEntry(book: "Acts", chapter: 24, verse: 10, texts: ["", "中文", "English"])])
    }
}

// 打真的外部網站，對照原本的 tests/test_bible_gateway_service.rb。
// 預設略過，要跑請設 REMA_NETWORK_TESTS=1（例如 REMA_NETWORK_TESTS=1 swift test）
final class NetworkBibleServiceTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REMA_NETWORK_TESTS"] == "1",
                          "網路測試預設略過，設 REMA_NETWORK_TESTS=1 才會跑")
    }

    private func query(_ service: any BibleService, _ str: String) async throws -> [BibleVerse] {
        try await service.query(SearchDsl.parse(str))
    }

    func testNivSingleVerse() async throws {
        let results = try await query(BibleGatewayService(version: "NIV"), "Gen1:1")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].book, "Genesis")
        XCTAssertTrue(results[0].text.lowercased().contains("beginning"))
    }

    // 挑一節 NIV/NKJV 譯文明顯不同的經文，確認 version 參數真的有生效
    func testNkjvAndNivReturnDifferentTranslations() async throws {
        let niv = try await query(BibleGatewayService(version: "NIV"), "Ps23:1")[0].text
        let nkjv = try await query(BibleGatewayService(version: "NKJV"), "Ps23:1")[0].text
        XCTAssertTrue(niv.lowercased().contains("lack nothing"), niv)
        XCTAssertTrue(nkjv.lowercased().contains("shall not want"), nkjv)
    }

    func testKjvVerseRange() async throws {
        let results = try await query(BibleGatewayService(version: "KJV"), "Gen1:1-3")
        XCTAssertEqual(results.map(\.verse), [1, 2, 3])
    }

    func testSpringBible() async throws {
        let results = try await query(SpringBibleService(), "創1:1-2")
        XCTAssertEqual(results.map(\.verse), [1, 2])
        XCTAssertTrue(results[0].text.contains("神創造天地"), results[0].text)
    }

    func testHolyBibleKorean() async throws {
        let results = try await query(HolyBibleKoreanService(), "創1:1")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.text.contains("하나님") ?? false, results.first?.text ?? "")
    }
}

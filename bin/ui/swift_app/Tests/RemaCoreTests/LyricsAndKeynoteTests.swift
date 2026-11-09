import XCTest
@testable import RemaCore

final class LyricsParserTests: XCTestCase {
    func testParsesHeaderAndSections() {
        let text = """
        #! line=3
        #! placeholders=kr,cn,en

        # Chorus

        영광의 주님
        榮光的 主神
        You are Glorious

        예수 영광의 주님
        耶穌 榮光的 主神
        Jesus You are glorious

        # end Chorus

        # Verse
        주와 같은 분은 없네
        世上無人 與你同等
        There's no one can stand against.
        # end Verse
        """
        let result = LyricsParser.parse(text)
        XCTAssertEqual(result.lineCount, 3)
        XCTAssertEqual(result.placeholders, ["kr", "cn", "en"])
        XCTAssertEqual(result.sections.map(\.name), ["Chorus", "Verse"])
        XCTAssertEqual(result.sections[0].slideGroups.count, 2)
        XCTAssertEqual(result.sections[0].slideGroups[1], ["예수 영광의 주님", "耶穌 榮光的 主神", "Jesus You are glorious"])
        XCTAssertEqual(result.sections[1].slideGroups, [["주와 같은 분은 없네", "世上無人 與你同等", "There's no one can stand against."]])
    }

    func testLinesOutsideSectionsAreIgnored() {
        let result = LyricsParser.parse("stray\n# A\nx\n# end A\nstray2")
        XCTAssertEqual(result.sections, [LyricsParser.Section(name: "A", slideGroups: [["x"]])])
    }

    func testUnterminatedSectionIsFlushed() {
        let result = LyricsParser.parse("# A\nx\ny")
        XCTAssertEqual(result.sections[0].slideGroups, [["x", "y"]])
    }
}

final class KeynoteRunnerTests: XCTestCase {
    func testQuoteEscapesBackslashAndDoubleQuote() {
        XCTAssertEqual(KeynoteRunner.q(#"a"b\c"#), #""a\"b\\c""#)
    }

    func testBuildScriptUsesSlideOneLayoutByDefault() {
        let script = KeynoteRunner.buildScript(
            document: URL(fileURLWithPath: "/tmp/t.key"), slideGroups: [["一", "two"]], placeholders: ["cn", "en"],
            exportDir: URL(fileURLWithPath: "/tmp/out/keynote_export_x"), masterName: nil, keepOpen: false)
        XCTAssertTrue(script.contains("set baseLayout to base slide of slide 1"))
        XCTAssertTrue(script.contains(#"if object text of t is equal to "cn" then"#))
        XCTAssertTrue(script.contains(#"set object text of t to "two""#))
        XCTAssertTrue(script.contains(#"export to POSIX file "/tmp/out/keynote_export_x""#))
        XCTAssertTrue(script.contains("close saving no"))
        XCTAssertFalse(script.contains("activate"))
    }

    func testBuildScriptWithMasterAndKeepOpen() {
        let script = KeynoteRunner.buildScript(
            document: URL(fileURLWithPath: "/tmp/t.key"), slideGroups: [["x"]], placeholders: ["cn"],
            exportDir: nil, masterName: "Title Only", keepOpen: true)
        XCTAssertTrue(script.contains(#"set baseLayout to slide layout "Title Only""#))
        XCTAssertTrue(script.contains("save doc"))
        XCTAssertTrue(script.contains("activate"))
        XCTAssertFalse(script.contains("export to"))
    }

    // 只驗證 AppleScript 語法能被 osascript 編譯，不真的叫 Keynote
    func testBuildScriptCompiles() throws {
        let script = KeynoteRunner.buildScript(
            document: URL(fileURLWithPath: "/tmp/t.key"), slideGroups: [["含\"引號\"", "line\nbreak"]], placeholders: ["a", "b"],
            exportDir: URL(fileURLWithPath: "/tmp/out"), masterName: nil, keepOpen: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("rema_test_\(UUID().uuidString).scpt")
        defer { try? FileManager.default.removeItem(at: output) }
        process.arguments = ["-o", output.path, "-e", script]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testExportedImagesSortNumerically() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rema_export_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for n in [10, 2, 1] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(String(format: "keynote_export_x.%03d.png", n)).path, contents: Data())
        }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("notes.txt").path, contents: Data())
        XCTAssertEqual(KeynoteRunner.exportedImages(in: dir).map(\.lastPathComponent),
                       ["keynote_export_x.001.png", "keynote_export_x.002.png", "keynote_export_x.010.png"])
    }

    func testMoveAndRenameExportedSlides() throws {
        let fm = FileManager.default
        let out = fm.temporaryDirectory.appendingPathComponent("rema_out_\(UUID().uuidString)")
        let export = out.appendingPathComponent("keynote_export_x")
        try fm.createDirectory(at: export, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: out) }
        for n in 1...3 { fm.createFile(atPath: export.appendingPathComponent("keynote_export_x.00\(n).png").path, contents: Data()) }

        let entries = [
            BibleQueryEntry(book: "Acts", chapter: 6, verse: 1, texts: []),
            BibleQueryEntry(book: "Acts", chapter: 6, verse: 2, texts: []),
        ]
        let warning = try BibleKeynoteGenerator.moveAndRenameExportedSlides(from: export, to: out, entries: entries)
        XCTAssertNotNil(warning)
        XCTAssertFalse(fm.fileExists(atPath: export.path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: out.path).sorted(), ["01_使徒行傳6-1.png", "02_使徒行傳6-2.png", "03.png"])
    }

    func testUniqueKeynotePathSanitizesName() {
        let path = BibleKeynoteGenerator.uniqueKeynotePath(in: URL(fileURLWithPath: "/nonexistent"), rawText: "創1:1\n出2:3")
        XCTAssertEqual(path.lastPathComponent, "創1-1-出2-3.key")
    }
}

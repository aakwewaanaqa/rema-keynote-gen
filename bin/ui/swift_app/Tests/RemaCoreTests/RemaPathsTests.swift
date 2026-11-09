import XCTest
@testable import RemaCore

final class RemaPathsTests: XCTestCase {
    func testInstallTemplatesCopiesOnlyMissingKeyFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("bundle")
        let destination = root.appendingPathComponent("Templates")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        try "bundled".write(to: source.appendingPathComponent("a.key"), atomically: true, encoding: .utf8)
        try "bundled".write(to: source.appendingPathComponent("b.key"), atomically: true, encoding: .utf8)
        try "ignored".write(to: source.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        // 使用者改過的範本不能被 bundle 裡的版本蓋掉
        try "edited".write(to: destination.appendingPathComponent("b.key"), atomically: true, encoding: .utf8)

        RemaPaths.installTemplates(from: source, to: destination)

        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("a.key"), encoding: .utf8), "bundled")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("b.key"), encoding: .utf8), "edited")
        XCTAssertFalse(fm.fileExists(atPath: destination.appendingPathComponent("readme.txt").path))
    }

    func testBibleSourceIsUnderApplicationSupport() {
        XCTAssertTrue(RemaPaths.bibleSource.path.hasSuffix("Application Support/RemaKeynoteGen/bible_src"))
    }
}

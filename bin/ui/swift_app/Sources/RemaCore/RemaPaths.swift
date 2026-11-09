import Foundation

public enum RemaPaths {
    // App 一律在這台機器的原始碼樹裡編譯、執行（見 start.command / package_app.sh），
    // 所以用 #filePath 回推專案根目錄：Sources/RemaCore/RemaPaths.swift 往上六層
    // （RemaCore → Sources → swift_app → ui → bin → 專案根目錄）
    public static let repositoryRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url
    }()

    // 本機聖經資料（LocalBibleService），git clone 在專案根目錄下，不進版控
    public static var bibleSource: URL {
        repositoryRoot.appendingPathComponent("bible_src")
    }
}

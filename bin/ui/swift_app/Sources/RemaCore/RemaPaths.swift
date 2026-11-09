import Foundation

public enum RemaPaths {
    // App 自己的資料夾：~/Library/Application Support/RemaKeynoteGen
    // 範本、本機聖經都放這裡，不再依賴專案原始碼樹的位置
    public static let applicationSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("RemaKeynoteGen")
    }()

    // 本機聖經資料（LocalBibleService）：整包 bible_src 有 ~94MB，不包進 App，
    // 由 install.command / start.command（bin/setup_bible_src.sh）clone 或從舊位置搬過來
    public static var bibleSource: URL {
        applicationSupport.appendingPathComponent("bible_src")
    }

    // 使用者的 Keynote 範本資料夾，挑範本檔的面板預設從這裡開
    public static var templates: URL {
        applicationSupport.appendingPathComponent("Templates")
    }

    // package_app.sh 把專案的 keynotes/*.key 包進 App 的 Resources/Templates，
    // App 啟動時複製到 templates；只補缺的，使用者改過或自己放的範本不會被蓋掉
    public static func installBundledTemplates(from bundle: Bundle = .main) {
        guard let source = bundle.resourceURL?.appendingPathComponent("Templates") else { return }
        installTemplates(from: source, to: templates)
    }

    static func installTemplates(from source: URL, to destination: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in files where file.pathExtension == "key" {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: target.path) {
                try? fm.copyItem(at: file, to: target)
            }
        }
    }
}

import Foundation

// 同一節經文、單一譯本的內容。service 是來源 token（fhl/niv/nkjv/gae/local），
// translation 是給人看的來源名稱（信望愛 CUV/NIV/...）。book 會跟著這個譯本的語言變
// （中文譯本顯示中文書名、NIV/NKJV 顯示英文書名、개역개정 顯示韓文書名），所以放在這裡而不是外層。
struct VerseTranslation: Decodable, Hashable {
    var service: String
    var translation: String
    var book: String
    var content: String
}

// 同一節經文，底下疊多個譯本——對照 advanced_bible_query_cli.rb 輸出的 verses 陣列，
// 一節一個 item，不是一節×一譯本一個 item
struct QueriedVerseGroup: Decodable, Hashable {
    var chapter: Int
    var verse: Int
    var translations: [VerseTranslation]
}

struct QueryResult: Decodable {
    let status: String?
    let verses: [QueriedVerseGroup]?
    let error: String?
}

struct QueryError: Error {
    let message: String
    // CLI 側 warn 印出的診斷內容（例如 SpringBibleService 重試紀錄），拿去給彈窗複製用
    let detail: String?

    init(message: String, detail: String? = nil) {
        self.message = message
        self.detail = detail
    }
}

func runBibleQueryCLI(scriptDir: URL, rawText: String, enabledTokens: String)
    -> Result<(String, [QueriedVerseGroup]), QueryError>
{
    let cliPath = scriptDir.appendingPathComponent("advanced_bible_query_cli.rb")

    let process = Process()
    // 從 Xcode Build & Run 啟動的 process，PATH 裡沒有 ~/.rbenv/shims，
    // `env ruby` 會掉回 macOS 內建的系統 Ruby（版本很舊、跟 rbenv 管理的版本行為不一致），
    // 所以直接指到 rbenv shim，不要依賴 PATH 去猜是哪個 ruby
    let rbenvRuby = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".rbenv/shims/ruby")
    if FileManager.default.isExecutableFile(atPath: rbenvRuby.path) {
        process.executableURL = rbenvRuby
        process.arguments = [cliPath.path, rawText, enabledTokens]
    } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ruby", cliPath.path, rawText, enabledTokens]
    }

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        return .failure(QueryError(message: "無法啟動 ruby: \(error.localizedDescription)"))
    }
    process.waitUntilExit()

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    // 不管成功或失敗都先讀出來：CLI 內部的 warn（例如 SpringBibleService 重試紀錄）都是走這條
    // stderr pipe，只有在真的解析失敗時才印出來的話，逾時之類「stdout 仍是合法 JSON」的情境
    // 就會把這些診斷資訊直接丟掉，Xcode Console 也看不到（因為被導去這個 Pipe 而不是繼承的 stderr）
    let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    guard let decoded = try? JSONDecoder().decode(QueryResult.self, from: data) else {
        let rawOutput = String(data: data, encoding: .utf8) ?? ""
        let detail = [stderrText, rawOutput].filter { !$0.isEmpty }.joined(separator: "\n")
        return .failure(QueryError(message: "無法解析輸出" + (detail.isEmpty ? "" : ": \(detail)"), detail: detail))
    }
    if let error = decoded.error {
        return .failure(QueryError(message: error, detail: stderrText))
    }
    return .success((decoded.status ?? "", decoded.verses ?? []))
}

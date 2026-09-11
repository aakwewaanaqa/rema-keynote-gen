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

// 從 Xcode Build & Run 啟動的 process，PATH 裡沒有 ~/.rbenv/shims，
// `env ruby` 會掉回 macOS 內建的系統 Ruby（版本很舊、跟 rbenv 管理的版本行為不一致），
// 所以直接指到 rbenv shim，不要依賴 PATH 去猜是哪個 ruby
private func configureRubyProcess(_ process: Process, scriptPath: String, arguments: [String]) {
    let rbenvRuby = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".rbenv/shims/ruby")
    if FileManager.default.isExecutableFile(atPath: rbenvRuby.path) {
        process.executableURL = rbenvRuby
        process.arguments = [scriptPath] + arguments
    } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ruby", scriptPath] + arguments
    }
}

func runBibleQueryCLI(scriptDir: URL, rawText: String, enabledTokens: String)
    -> Result<(String, [QueriedVerseGroup]), QueryError>
{
    let cliPath = scriptDir.appendingPathComponent("advanced_bible_query_cli.rb")

    let process = Process()
    configureRubyProcess(process, scriptPath: cliPath.path, arguments: [rawText, enabledTokens])

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

private struct KeynotePlaceholderPayload: Encodable {
    var placeholder: String
    var format: String
}

struct GenerateKeynoteError: Error {
    let message: String
    let detail: String?

    init(message: String, detail: String? = nil) {
        self.message = message
        self.detail = detail
    }
}

private struct GenerateKeynoteResult: Decodable {
    let status: String?
    let outputDir: String?
    let errors: [String]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status
        case outputDir = "output_dir"
        case errors
        case error
    }
}

// 對照 generate_keynote_cli.rb：查經文 -> 依 placeholders 範本代換 -> KeynoteRunner(osascript) 套進範本輸出投影片。
// 跟查詢本身分開一支 CLI，因為這一步真的會動 Keynote App（開檔、加投影片、匯出、關檔），
// 觸發時機（按下「產生 Keynote」）跟查詢預覽（按下「查詢」）不一樣。
func runGenerateKeynoteCLI(
    scriptDir: URL,
    rawText: String,
    enabledTokens: String,
    templatePath: String,
    outputDir: String,
    placeholders: [KeynotePlaceholder]
) -> Result<(String, String?, [String]), GenerateKeynoteError> {
    let cliPath = scriptDir.appendingPathComponent("generate_keynote_cli.rb")

    let payload = placeholders.map { KeynotePlaceholderPayload(placeholder: $0.placeholder, format: $0.format) }
    guard let placeholdersData = try? JSONEncoder().encode(payload),
          let placeholdersJSON = String(data: placeholdersData, encoding: .utf8)
    else {
        return .failure(GenerateKeynoteError(message: "無法編碼 placeholder 資料"))
    }

    let process = Process()
    configureRubyProcess(
        process,
        scriptPath: cliPath.path,
        arguments: [rawText, enabledTokens, templatePath, outputDir, placeholdersJSON]
    )

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        return .failure(GenerateKeynoteError(message: "無法啟動 ruby: \(error.localizedDescription)"))
    }
    process.waitUntilExit()

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    guard let decoded = try? JSONDecoder().decode(GenerateKeynoteResult.self, from: data) else {
        let rawOutput = String(data: data, encoding: .utf8) ?? ""
        let detail = [stderrText, rawOutput].filter { !$0.isEmpty }.joined(separator: "\n")
        return .failure(GenerateKeynoteError(message: "無法解析輸出" + (detail.isEmpty ? "" : ": \(detail)"), detail: detail))
    }
    if let error = decoded.error {
        return .failure(GenerateKeynoteError(message: error, detail: stderrText))
    }
    return .success((decoded.status ?? "", decoded.outputDir, decoded.errors ?? []))
}

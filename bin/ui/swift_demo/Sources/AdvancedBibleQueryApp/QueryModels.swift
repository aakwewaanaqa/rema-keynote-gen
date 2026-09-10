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
}

struct KeynotePlaceholder: Identifiable, Hashable {
    var id: UUID = UUID()
    var placeholder: String
    var format: String
}

func runBibleQueryCLI(scriptDir: URL, rawText: String, enabledTokens: String)
    -> Result<(String, [QueriedVerseGroup]), QueryError>
{
    let cliPath = scriptDir.appendingPathComponent("advanced_bible_query_cli.rb")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["ruby", cliPath.path, rawText, enabledTokens]

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
    guard let decoded = try? JSONDecoder().decode(QueryResult.self, from: data) else {
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let rawOutput = String(data: data, encoding: .utf8) ?? ""
        let detail = [stderrText, rawOutput].filter { !$0.isEmpty }.joined(separator: "\n")
        return .failure(QueryError(message: "無法解析輸出" + (detail.isEmpty ? "" : ": \(detail)")))
    }
    if let error = decoded.error {
        return .failure(QueryError(message: error))
    }
    return .success((decoded.status ?? "", decoded.verses ?? []))
}

import Foundation

// 對照 advanced_bible_query_cli.rb 輸出的單節經文，service 是來源 token（fhl/niv/nkjv/gae/local），
// translation 是給人看的來源名稱（信望愛 CUV/NIV/...）
struct QueriedVerse: Decodable, Hashable {
    var service: String
    var translation: String
    var book: String
    var chapter: Int
    var verse: Int
    var content: String
}

struct QueryResult: Decodable {
    let status: String?
    let verses: [QueriedVerse]?
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
    -> Result<(String, [QueriedVerse]), QueryError>
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

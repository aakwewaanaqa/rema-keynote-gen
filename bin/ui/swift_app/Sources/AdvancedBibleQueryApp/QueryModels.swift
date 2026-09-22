import Foundation

// 同一節經文、單一譯本的內容。service 是來源 token（fhl/niv/nkjv/gae/local），
// translation 是給人看的來源名稱（信望愛 CUV/NIV/...）。book 會跟著這個譯本的語言變
// （中文譯本顯示中文書名、NIV/NKJV 顯示英文書名、개역개정 顯示韓文書名），所以放在這裡而不是外層。
struct VerseTranslation: Codable, Hashable {
    var service: String
    var translation: String
    var book: String
    var content: String
}

// 同一節經文，底下疊多個譯本——對照 advanced_bible_query_cli.rb 輸出的 verses 陣列，
// 一節一個 item，不是一節×一譯本一個 item
struct QueriedVerseGroup: Codable, Hashable {
    var chapter: Int
    var verse: Int
    var translations: [VerseTranslation]
}

struct QueryResult: Decodable {
    let status: String?
    let verses: [QueriedVerseGroup]?
    let error: String?
    // 個別查詢來源掛掉（例如某聖經網站故障）的錯誤訊息，跟整體查詢成功與否無關——
    // 就算這個陣列不是空的，status/verses 仍然是其他來源正常查到的結果
    let sourceErrors: [String]?

    enum CodingKeys: String, CodingKey {
        case status, verses, error
        case sourceErrors = "source_errors"
    }
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

// 使用者按「取消」時丟出的錯誤，跟真正查詢失敗分開判斷，
// 這樣 UI 才知道不用彈錯誤詳情視窗，只要把狀態列切成「已取消查詢」就好
struct QueryCancelledError: Error {}

// command 是 "query" 或 "generate"，對照 cli_entry.rb 的兩個分支。
//
// 優先找 .app/Contents/Resources/rubycli——那是 build_rubycli.sh 用 tebako 把 ruby 直譯器、
// nokogiri 等 gem、src/、bible_src/ 全部壓成的單一可執行檔，不依賴這台機器裝了什麼 ruby，
// AirDrop 給別人也能直接跑。
//
// 找不到就 fallback 回「這台機器上的原始碼樹 + rbenv ruby」，給 swift run / Xcode Build & Run
// 這種開發情境用：PATH 裡沒有 ~/.rbenv/shims，`env ruby` 會掉回 macOS 內建的系統 Ruby
// （版本很舊、跟 rbenv 管理的版本行為不一致），所以直接指到 rbenv shim，不要依賴 PATH 去猜。
private func configureRubyProcess(_ process: Process, command: String, arguments: [String]) {
    if let bundledCLI = Bundle.main.url(forResource: "rubycli", withExtension: nil),
       FileManager.default.isExecutableFile(atPath: bundledCLI.path) {
        process.executableURL = bundledCLI
        process.arguments = [command] + arguments
        return
    }

    let scriptName = command == "query" ? "advanced_bible_query_cli.rb" : "generate_keynote_cli.rb"
    // #filePath 在 Sources/AdvancedBibleQueryApp/QueryModels.swift，
    // 往上三層回到 swift_app 目錄，對照 advanced_bible_query_cli.rb / generate_keynote_cli.rb 所在位置
    let scriptPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(scriptName)
        .path

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

// 跑 advanced_bible_query_cli.rb 的查詢任務，跟舊版 runBibleQueryCLI（單純同步等到底）不一樣的地方：
// 這支能被使用者按下「取消」時真的把底層的 ruby process 終止掉，不是單純放著不管結果。
//
// stdout/stderr 都用 readabilityHandler 非同步邊產生邊讀，而不是等 waitUntilExit() 後才一次讀完——
// 一次讀完是舊版的做法，查詢結果的 JSON 只要大一點（塞爆 pipe 緩衝區）就有機會卡死：
// 子行程寫 stdout 寫到緩衝區滿了會被系統擋住，但我們這邊還在等它先結束才要讀，雙方互等。
// 所有共用的可變狀態（緩衝區、是否取消）都只能在 ioQueue 這條序列 queue 上動，
// 避免兩個 pipe 的 readabilityHandler（各自跑在系統管理的併發 queue 上）互相搶。
final class BibleQueryTask {
    private let process = Process()
    private let ioQueue = DispatchQueue(label: "BibleQueryTask.io")
    private var stdoutData = Data()
    private var stderrText = ""
    private var isCancelled = false
    private var didFinish = false

    func start(
        rawText: String,
        enabledTokens: String,
        completion: @escaping (Result<(String, [QueriedVerseGroup], [String]), Error>) -> Void
    ) {
        configureRubyProcess(process, command: "query", arguments: [rawText, enabledTokens])

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.ioQueue.async { self.stdoutData.append(data) }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self, let text = String(data: data, encoding: .utf8) else { return }
            self.ioQueue.async { self.stderrText += text }
        }

        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.ioQueue.async {
                // process 結束不代表兩個 readabilityHandler 都已經把最後一批資料收完，
                // 這裡先關掉 handler 再用 readDataToEndOfFile 把管線剩下的內容一次讀乾淨
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let leftoverOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                if !leftoverOut.isEmpty { self.stdoutData.append(leftoverOut) }
                let leftoverErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !leftoverErr.isEmpty, let text = String(data: leftoverErr, encoding: .utf8) {
                    self.stderrText += text
                }
                self.finish(completion: completion)
            }
        }

        do {
            try process.run()
        } catch {
            completion(.failure(QueryError(message: "無法啟動 ruby: \(error.localizedDescription)")))
        }
    }

    // 只能在 ioQueue 上呼叫
    private func finish(completion: @escaping (Result<(String, [QueriedVerseGroup], [String]), Error>) -> Void) {
        guard !didFinish else { return }
        didFinish = true
        let stdoutData = self.stdoutData
        let stderrText = self.stderrText
        let wasCancelled = self.isCancelled

        DispatchQueue.main.async {
            if wasCancelled {
                completion(.failure(QueryCancelledError()))
                return
            }
            guard let decoded = try? JSONDecoder().decode(QueryResult.self, from: stdoutData) else {
                let rawOutput = String(data: stdoutData, encoding: .utf8) ?? ""
                let detail = [stderrText, rawOutput].filter { !$0.isEmpty }.joined(separator: "\n")
                completion(.failure(QueryError(message: "無法解析輸出" + (detail.isEmpty ? "" : ": \(detail)"), detail: detail)))
                return
            }
            if let error = decoded.error {
                completion(.failure(QueryError(message: error, detail: stderrText)))
                return
            }
            completion(.success((decoded.status ?? "", decoded.verses ?? [], decoded.sourceErrors ?? [])))
        }
    }

    // 真的把底層 ruby process 終止掉（SIGTERM），不是單純不理會結果——
    // 不然使用者取消後那個查詢還在背景繼續打外部聖經網站，下次查詢又會多起一支同時在跑
    func cancel() {
        ioQueue.async { self.isCancelled = true }
        process.terminate()
    }
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
    rawText: String,
    enabledTokens: String,
    templatePath: String,
    outputDir: String,
    placeholders: [KeynotePlaceholder]
) -> Result<(String, String?, [String]), GenerateKeynoteError> {
    let payload = placeholders.map { KeynotePlaceholderPayload(placeholder: $0.placeholder, format: $0.format) }
    guard let placeholdersData = try? JSONEncoder().encode(payload),
          let placeholdersJSON = String(data: placeholdersData, encoding: .utf8)
    else {
        return .failure(GenerateKeynoteError(message: "無法編碼 placeholder 資料"))
    }

    let process = Process()
    configureRubyProcess(
        process,
        command: "generate",
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

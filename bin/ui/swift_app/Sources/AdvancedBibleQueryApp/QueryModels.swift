import Foundation
@_exported import RemaCore

// 查詢、產生 Keynote 的邏輯都在 RemaCore（以前是透過 Process 呼叫 Ruby 的 *_cli.rb，JSON 交換資料），
// 這裡只是把 RemaCore 包成 UI 好用的形狀：錯誤統一成帶 detail 的型別、callback 回到 main thread。
// @_exported 讓 App 裡其他檔案不用各自 import RemaCore 就能用 QueriedVerseGroup 這些型別

struct QueryError: Error {
    let message: String
    // 給彈窗複製用的完整診斷內容
    let detail: String?

    init(message: String, detail: String? = nil) {
        self.message = message
        self.detail = detail
    }
}

// 使用者按「取消」時丟出的錯誤，跟真正查詢失敗分開判斷，
// 這樣 UI 才知道不用彈錯誤詳情視窗，只要把狀態列切成「已取消查詢」就好
struct QueryCancelledError: Error {}

// 查經文的任務。使用者按下「取消」時真的把進行中的網路請求取消掉，
// 不然取消後那個查詢還在背景繼續打外部聖經網站，下次查詢又會多起一支同時在跑
final class BibleQueryTask {
    private var task: Task<Void, Never>?

    func start(
        rawText: String,
        enabledTokens: String,
        completion: @escaping (Result<(String, [QueriedVerseGroup], [String]), Error>) -> Void
    ) {
        let sources = BibleSource.parse(tokens: enabledTokens)
        task = Task {
            let result: Result<(String, [QueriedVerseGroup], [String]), Error>
            do {
                let outcome = try await BibleVerseQuery.run(rawText, sources: sources)
                result = .success((outcome.status, outcome.verses, outcome.sourceErrors))
            } catch is CancellationError {
                result = .failure(QueryCancelledError())
            } catch {
                result = Task.isCancelled
                    ? .failure(QueryCancelledError())
                    : .failure(QueryError(message: error.localizedDescription, detail: String(describing: error)))
            }
            await MainActor.run { completion(result) }
        }
    }

    func cancel() {
        task?.cancel()
    }
}

struct GenerateKeynoteError: Error {
    let message: String
    let detail: String?

    init(message: String, detail: String? = nil) {
        self.message = message
        self.detail = detail
    }

    init(_ error: Error) {
        self.init(message: error.localizedDescription)
    }
}

typealias KeynoteOpenDocument = KeynoteRunner.OpenDocument

// 查經文 -> 依 placeholders 範本代換 -> KeynoteRunner(osascript) 套進範本輸出投影片。
// 跟查詢本身分開，因為這一步真的會動 Keynote App（開檔、加投影片、匯出、存檔），
// 觸發時機（按下「產生 Keynote」）跟查詢預覽（按下「查詢」）不一樣。
// 回傳 (狀態, 輸出資料夾, 簡報路徑, 警告)
func generateBibleKeynote(
    rawText: String,
    enabledTokens: String,
    templatePath: String,
    outputDir: String,
    placeholders: [KeynotePlaceholder],
    masterName: String?,
    exportImages: Bool
) async -> Result<(String, String?, String?, [String]), GenerateKeynoteError> {
    do {
        let outcome = try await BibleKeynoteGenerator.generate(
            rawText: rawText,
            sources: BibleSource.parse(tokens: enabledTokens),
            template: URL(fileURLWithPath: templatePath),
            outputDir: URL(fileURLWithPath: outputDir),
            placeholders: placeholders.map { .init(placeholder: $0.placeholder, format: $0.format) },
            masterName: masterName,
            exportImages: exportImages
        )
        return .success((outcome.status, outcome.outputDir.path, outcome.keynotePath.path, outcome.warnings))
    } catch {
        return .failure(GenerateKeynoteError(message: "產生失敗: \(error.localizedDescription)"))
    }
}

// 叫 Keynote 開範本讀出所有母片名稱（讀完就關檔不存），給產生 Keynote 前挑母片用。
// 錯誤沿用 GenerateKeynoteError，因為這一步就是產生流程的一部分
func listKeynoteLayouts(templatePath: String) -> Result<[String], GenerateKeynoteError> {
    guard FileManager.default.fileExists(atPath: templatePath) else {
        return .failure(GenerateKeynoteError(message: "找不到範本檔案: \(templatePath)"))
    }
    do {
        return .success(try KeynoteRunner.layoutNames(template: URL(fileURLWithPath: templatePath)))
    } catch {
        return .failure(GenerateKeynoteError(
            message: "讀取母片失敗（請確認 Keynote 已安裝、範本檔案可開啟）",
            detail: error.localizedDescription))
    }
}

// 列出 Keynote 目前開著（且存過檔）的文件，給挑範本時直接選。
// Keynote 沒在跑就回空陣列，不會把 Keynote 叫起來
func listKeynoteOpenDocuments() -> Result<[KeynoteOpenDocument], GenerateKeynoteError> {
    do {
        return .success(try KeynoteRunner.openDocuments())
    } catch {
        return .failure(GenerateKeynoteError(message: "讀取 Keynote 開啟中的檔案失敗：\(error.localizedDescription)"))
    }
}

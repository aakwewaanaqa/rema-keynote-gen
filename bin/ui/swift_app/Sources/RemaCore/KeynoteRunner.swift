import Foundation

// 透過 osascript 操作 Keynote，對照原本的 src/keynote_runner.rb
public enum KeynoteRunner {
    static let app = "Keynote"

    public struct OpenDocument: Codable, Hashable, Sendable {
        public let path: String
        public let modified: Bool  // 有未儲存的變更——範本走的是磁碟上的檔案，那些變更不會反映在產生的投影片上
    }

    // Keynote 的「export ... as slide images」會自己去建立匯出目標資料夾，如果那個資料夾已經存在
    // （例如使用者直接選了 outputDir 本身，這裡又先建過一次）就會匯出失敗
    // （"could not be exported... changes might be lost"）。所以只確保 outputDir 這個「容器」存在，
    // 實際匯出目標另外取一個當下必定不存在的子資料夾名稱，交給 Keynote 自己建立。
    // masterName 是範本裡的母片（slide layout）名稱，nil/空字串就沿用範本 slide 1 的母片（見 buildScript 的說明）。
    // keepOpenPath 有給的話，範本改複製到這個路徑（不是暫存資料夾），產生完存檔並留在 Keynote 裡開著，
    // 讓使用者可以接著改、⌘S 也存得回這個檔；沒給就用暫存複本、產生完不存檔直接關掉。
    // exportImages: false 就只貼投影片不匯出圖片，回傳的匯出資料夾是 nil（只在 keepOpenPath 有給時才有意義）。
    // 回傳實際的匯出資料夾（呼叫端要自己把裡面的 PNG 搬出來、刪掉這個暫存資料夾）
    @discardableResult
    public static func export(
        template: URL,
        slideGroups: [[String]],
        placeholders: [String],
        outputDir: URL,
        masterName: String? = nil,
        keepOpenPath: URL? = nil,
        exportImages: Bool = true
    ) throws -> URL? {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let exportDir = exportImages ? uniqueExportDir(in: outputDir) : nil

        if let keepOpenPath {
            try fm.copyItem(at: template, to: keepOpenPath)
            try runOsascript(buildScript(
                document: keepOpenPath, slideGroups: slideGroups, placeholders: placeholders,
                exportDir: exportDir, masterName: masterName, keepOpen: true))
        } else {
            try withTemplateCopy(template) { copy in
                _ = try runOsascript(buildScript(
                    document: copy, slideGroups: slideGroups, placeholders: placeholders,
                    exportDir: exportDir, masterName: masterName, keepOpen: false))
            }
        }
        return exportDir
    }

    // 列出範本裡所有母片名稱，給使用者挑 masterName 用。要真的叫 Keynote 開檔才讀得到，
    // 讀完就 close saving no。開的是暫存複本（見 withTemplateCopy），範本就算正開著也不會被關掉
    public static func layoutNames(template: URL) throws -> [String] {
        try withTemplateCopy(template) { copy in
            let script = """
            tell application \(q(app))
              set doc to open POSIX file \(q(copy.path))
              delay 2
              tell doc
                set layoutNames to name of every slide layout
                close saving no
              end tell
            end tell
            set AppleScript's text item delimiters to linefeed
            return layoutNames as text
            """
            return try runOsascript(script)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    // 列出 Keynote 目前開著、而且已經存過檔的文件（沒存過檔的沒有路徑，沒辦法拿來當範本），
    // 給使用者直接挑來當範本。Keynote 沒在跑就回傳空清單，不要為了問這個把 Keynote 叫起來
    public static func openDocuments() throws -> [OpenDocument] {
        let script = """
        if application \(q(app)) is not running then return ""
        set out to ""
        tell application \(q(app))
          repeat with d in documents
            try
              set f to file of d
              if f is not missing value then
                set out to out & (POSIX path of f) & tab & ((modified of d) as text) & linefeed
              end if
            end try
          end repeat
        end tell
        return out
        """
        return try runOsascript(script)
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard let path = parts.first, !path.isEmpty else { return nil }
                var cleaned = String(path)
                if cleaned.hasSuffix("/") { cleaned.removeLast() }
                return OpenDocument(path: cleaned, modified: parts.count > 1 && parts[1] == "true")
            }
    }

    // 範本開的一律是暫存資料夾裡的複本，不是範本本身：使用者可能正在 Keynote 裡開著同一個範本，
    // 直接 open 原檔的話 Keynote 只會把那份已開的文件拉到最前面，後面的刪投影片、close saving no
    // 就會作用在使用者自己的文件上，未儲存的修改直接不見。.key 有可能是資料夾形式的 package，copyItem 會整包複製
    static func withTemplateCopy<T>(_ template: URL, _ body: (URL) throws -> T) throws -> T {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("keynote_template_\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let copy = dir.appendingPathComponent(template.lastPathComponent)
        try fm.copyItem(at: template, to: copy)
        return try body(copy)
    }

    static func uniqueExportDir(in outputDir: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let base = "keynote_export_\(formatter.string(from: Date()))"
        var dir = outputDir.appendingPathComponent(base)
        var suffix = 1
        while FileManager.default.fileExists(atPath: dir.path) {
            dir = outputDir.appendingPathComponent("\(base)_\(suffix)")
            suffix += 1
        }
        return dir
    }

    // 新投影片一定要沿用範本 slide 1 的 base slide（版型），不然 `make new slide` 會套用
    // 佈景主題的預設版型，裡面文字框的內容（如 "Title"/"Text"）跟 placeholders 打的字串對不上，
    // `if object text of t is equal to ...` 永遠比對失敗，投影片就會整張空白（沒有任何文字被替換進去）。
    // 有指定 masterName 就改用那張母片，前提一樣是那張母片裡的文字框內容要跟 placeholders 對得上
    static func buildScript(
        document: URL, slideGroups: [[String]], placeholders: [String],
        exportDir: URL?, masterName: String?, keepOpen: Bool
    ) -> String {
        let baseLayout: String
        if let masterName, !masterName.isEmpty {
            baseLayout = "slide layout \(q(masterName))"
        } else {
            baseLayout = "base slide of slide 1"
        }

        let addSlides = slideGroups.map { group -> String in
            let setTexts = placeholders.enumerated().map { i, ph in
                let text = i < group.count ? group[i] : ""
                return """
                        if object text of t is equal to \(q(ph)) then
                          set object text of t to \(q(text))
                        end if
                """
            }.joined(separator: "\n")

            return """
                set s to (make new slide with properties {base slide:baseLayout})
                tell s
                  repeat with t in every text item
                    tell t
            \(setTexts)
                    end tell
                  end repeat
                end tell
            """
        }.joined(separator: "\n")

        var lines = ["tell application \(q(app))"]
        if keepOpen { lines.append("  activate") }
        lines += [
            "  set doc to open POSIX file \(q(document.path))",
            "  delay 2",
            "  tell doc",
            "    if (count of slides) > 1 then delete slides 2 thru (count of slides)",
            "    set baseLayout to \(baseLayout)",
            addSlides,
            "    delete slide 1",
        ]
        if let exportDir {
            lines.append("    export to POSIX file \(q(exportDir.path)) as slide images with properties {image format:PNG}")
        }
        lines += [
            keepOpen ? "    save doc" : "    close saving no",
            "  end tell",
            "end tell",
        ]
        return lines.joined(separator: "\n")
    }

    static func q(_ str: String) -> String {
        "\"" + str.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // 跑一段 AppleScript，回傳 stdout；失敗就把 osascript 的 stderr 當錯誤訊息丟出去。
    // 腳本從 stdin 餵進去（不是 -e），投影片一多腳本會很長，不要撞到參數長度上限
    @discardableResult
    static func runOsascript(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        stdin.fileHandleForWriting.write(Data(script.utf8))
        try stdin.fileHandleForWriting.close()

        // 兩個 pipe 都要在等 process 結束之前開始讀，不然輸出一多塞爆 pipe 緩衝區就會互等卡死
        var errData = Data()
        let errReader = Thread { errData = stderr.fileHandleForReading.readDataToEndOfFile() }
        errReader.start()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        while !errReader.isFinished { usleep(1000) }

        let output = String(decoding: outData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw RemaError("osascript 執行失敗" + (message.isEmpty ? "" : "：\(message)"))
        }
        return output.trimmingCharacters(in: .newlines)
    }

    // Keynote 匯出的 PNG 檔名是「暫存資料夾名稱.001.png」這種格式，用檔名裡的數字排序
    // （不是字串排序，避免超過 9 張時 "10" 排到 "2" 前面）
    public static func exportedImages(in exportDir: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: exportDir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { slideNumber($0) < slideNumber($1) }
    }

    private static func slideNumber(_ url: URL) -> Int {
        // 「keynote_export_20260912_120000.001.png」→ 取副檔名前最後一段數字
        let stem = url.deletingPathExtension().lastPathComponent
        return Int(stem.split(separator: ".").last ?? "") ?? 0
    }
}

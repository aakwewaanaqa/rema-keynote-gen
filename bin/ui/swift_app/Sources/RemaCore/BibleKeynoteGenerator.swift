import Foundation

// 查經文 -> 依 placeholder 範本代換 -> 透過 KeynoteRunner（osascript）把內容套進 Keynote 範本、輸出投影片，
// 對照原本的 bin/ui/swift_app/generate_keynote_cli.rb
public enum BibleKeynoteGenerator {
    public struct Placeholder: Sendable {
        public let placeholder: String  // 範本文字框裡的佔位字串
        public let format: String       // 例如 "{中書}{章}:{節}\n{中}"

        public init(placeholder: String, format: String) {
            self.placeholder = placeholder
            self.format = format
        }
    }

    public struct Outcome: Sendable {
        public let status: String
        public let outputDir: URL
        public let keynotePath: URL
        public let warnings: [String]
    }

    // masterName 為 nil/空字串就沿用範本 slide 1 的母片（見 KeynoteRunner.buildScript）。
    // exportImages 為 false 就只把投影片貼進新簡報（存成 .key 並保持開啟），不出 PNG
    public static func generate(
        rawText: String,
        sources: Set<BibleSource>,
        template: URL,
        outputDir: URL,
        placeholders: [Placeholder],
        masterName: String?,
        exportImages: Bool
    ) async throws -> Outcome {
        guard !rawText.isEmpty else { throw RemaError("缺少查詢字串") }
        guard FileManager.default.fileExists(atPath: template.path) else {
            throw RemaError("找不到範本檔案: \(template.path)")
        }
        guard !placeholders.isEmpty else { throw RemaError("至少需要一個 placeholder") }
        guard !sources.isEmpty else {
            let available = BibleSource.allCases.map(\.token).joined(separator: "/")
            throw RemaError("請至少勾選一個查詢來源（可用: \(available)）")
        }

        let outcome = try await BibleQuery.run(rawText, sources: BibleSource.querySources(enabled: sources))
        guard !outcome.entries.isEmpty else { throw RemaError("查無經文") }

        var warnings = outcome.sourceErrors
        let slideGroups = outcome.entries.map { entry in
            placeholders.map {
                BibleTemplate.renderPlaceholder($0.format, entry: entry, errors: &warnings, placeholderName: $0.placeholder)
            }
        }

        // 產生完的簡報另存成 .key 放在輸出資料夾（跟 PNG 一起），並留在 Keynote 裡開著讓使用者接著改
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let keynotePath = uniqueKeynotePath(in: outputDir, rawText: rawText)

        let exportDir: URL?
        do {
            exportDir = try KeynoteRunner.export(
                template: template,
                slideGroups: slideGroups,
                placeholders: placeholders.map(\.placeholder),
                outputDir: outputDir,
                masterName: masterName,
                keepOpenPath: keynotePath,
                exportImages: exportImages
            )
        } catch {
            let hint = (masterName ?? "").isEmpty ? "" : "、母片「\(masterName!)」存在於範本中"
            throw RemaError("Keynote 產生失敗（請確認 Keynote 已安裝、範本檔案可開啟\(hint)）\n\(error.localizedDescription)")
        }

        if let exportDir {
            if let warning = try moveAndRenameExportedSlides(from: exportDir, to: outputDir, entries: outcome.entries) {
                warnings.append(warning)
            }
        }

        var status = exportImages ? "已產生 \(slideGroups.count) 張投影片並匯出圖片" : "已貼上 \(slideGroups.count) 張投影片"
        if !warnings.isEmpty { status += "（\(warnings.count) 個警告）" }
        return Outcome(status: status, outputDir: outputDir, keynotePath: keynotePath, warnings: warnings)
    }

    // 檔名用查詢字串，看得出是哪段經文；路徑分隔字元、換行（多筆查詢可用換行分隔）都換掉，同名就加流水號
    static func uniqueKeynotePath(in outputDir: URL, rawText: String) -> URL {
        let replaced = rawText.replacingOccurrences(of: #"[/:\n\r]+"#, with: "-", options: .regularExpression)
        var name = String(replaced.trimmingCharacters(in: .whitespaces).prefix(60))
        if name.isEmpty { name = "經文" }

        var path = outputDir.appendingPathComponent("\(name).key")
        var suffix = 1
        while FileManager.default.fileExists(atPath: path.path) {
            path = outputDir.appendingPathComponent("\(name)_\(suffix).key")
            suffix += 1
        }
        return path
    }

    // Keynote 匯出的檔名（如 template.001.png）看不出對應哪節經文，這裡把檔名換成書卷/章/節，
    // 順便把檔案從 KeynoteRunner 的暫存 exportDir 搬回使用者選的 outputDir，搬完把已經空了的暫存資料夾刪掉。
    // entries 跟投影片是同一個順序，所以「第 N 張投影片」就對應 entries[N-1]。
    // 回傳數量對不上時的警告訊息
    static func moveAndRenameExportedSlides(from exportDir: URL, to outputDir: URL, entries: [BibleQueryEntry]) throws -> String? {
        let fm = FileManager.default
        let files = KeynoteRunner.exportedImages(in: exportDir)

        // 就算數量對不上也要把「每一張」都搬出去，不然對不上的那幾張會被留在 exportDir 裡
        for (i, file) in files.enumerated() {
            let newName: String
            if i < entries.count {
                let entry = entries[i]
                let book = Bible.book(code: entry.book)?.chinese ?? entry.book
                newName = String(format: "%02d_%@%d-%d.png", i + 1, book, entry.chapter, entry.verse)
            } else {
                newName = String(format: "%02d.png", i + 1)
            }
            let target = outputDir.appendingPathComponent(newName)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: file, to: target)
        }
        try? fm.removeItem(at: exportDir)

        guard !files.isEmpty, files.count != entries.count else { return nil }
        return "匯出的圖片數量（\(files.count)）跟經節數量（\(entries.count)）對不上，檔名可能對應不準確，已盡量重新命名"
    }
}

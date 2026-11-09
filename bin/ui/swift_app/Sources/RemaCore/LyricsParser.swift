import Foundation

// 解析 Rema 用歌詞 TXT，對照原本的 src/lyrics_parser.rb。格式見 README：
//   #! line=3
//   #! placeholders=kr,cn,en
//   # Chorus
//   （歌詞，空行分隔投影片）
//   # end Chorus
public enum LyricsParser {
    public struct Section: Equatable, Sendable {
        public let name: String
        public var slideGroups: [[String]]  // 每張投影片一組，每組裡一行對應一個 placeholder
    }

    public struct Result: Equatable, Sendable {
        public var lineCount = 1
        public var placeholders: [String] = []
        public var sections: [Section] = []  // 依檔案中出現的順序
    }

    public static func parse(contentsOf url: URL) throws -> Result {
        parse(try String(contentsOf: url, encoding: .utf8))
    }

    public static func parse(_ text: String) -> Result {
        var result = Result()
        var currentSection: Int?
        var currentGroup: [String] = []

        func flush() {
            if let currentSection, !currentGroup.isEmpty {
                result.sections[currentSection].slideGroups.append(currentGroup)
            }
            currentGroup = []
        }

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("#!") {
                let pair = line.dropFirst(2).trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
                let key = pair.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                let value = pair.count > 1 ? String(pair[1]) : ""
                switch key {
                case "line": result.lineCount = Int(value.trimmingCharacters(in: .whitespaces)) ?? 0
                case "placeholders": result.placeholders = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                default: break
                }
            } else if line.hasPrefix("# end "), line.count > "# end ".count {
                flush()
                currentSection = nil
            } else if line.hasPrefix("# "), line.count > 2 {
                let name = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                // 同名段落再出現一次就重新開始（Ruby 版是 hash 直接覆蓋）
                if let existing = result.sections.firstIndex(where: { $0.name == name }) {
                    result.sections[existing].slideGroups = []
                    currentSection = existing
                } else {
                    result.sections.append(Section(name: name, slideGroups: []))
                    currentSection = result.sections.count - 1
                }
            } else if line.isEmpty {
                flush()
            } else if currentSection != nil {
                currentGroup.append(line)
            }
        }
        flush()
        return result
    }
}

// 批次把一個資料夾裡的歌詞 .txt 套進 Keynote 範本、匯出 PNG，對照原本的 bin/main.rb。
// 輸出結構：<歌詞資料夾>/<歌名>/<段落名稱>/<段落名稱>.001.png
public enum LyricsBatchGenerator {
    public static func lyricsFiles(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // log 每完成一步就呼叫一次（可能在背景執行緒），回傳失敗的段落數
    @discardableResult
    public static func run(template: URL, lyricsFolder: URL, log: (String) -> Void) throws -> Int {
        let files = lyricsFiles(in: lyricsFolder)
        guard !files.isEmpty else { throw RemaError("資料夾內沒有 .txt 歌詞檔") }

        log("找到 \(files.count) 個歌詞檔")
        var failures = 0

        for file in files {
            let songName = file.deletingPathExtension().lastPathComponent
            let songDir = lyricsFolder.appendingPathComponent(songName)
            log("▶ \(songName)")

            let parsed: LyricsParser.Result
            do {
                parsed = try LyricsParser.parse(contentsOf: file)
            } catch {
                log("  讀取失敗：\(error.localizedDescription)")
                failures += 1
                continue
            }

            for section in parsed.sections {
                let outputDir = songDir.appendingPathComponent(section.name)
                do {
                    let exportDir = try KeynoteRunner.export(
                        template: template,
                        slideGroups: section.slideGroups,
                        placeholders: parsed.placeholders,
                        outputDir: outputDir
                    )
                    if let exportDir { try moveExportedSlides(from: exportDir, to: outputDir, sectionName: section.name) }
                    log("  \(section.name)（\(section.slideGroups.count) 張）完成")
                } catch {
                    log("  \(section.name)（\(section.slideGroups.count) 張）失敗：\(error.localizedDescription)")
                    failures += 1
                }
            }
        }

        log(failures == 0 ? "全部完成" : "完成，但有 \(failures) 個段落失敗")
        return failures
    }

    // KeynoteRunner.export 把圖片匯出到 outputDir 底下另一個暫存的 keynote_export_TIMESTAMP 子資料夾
    // （避開 Keynote「目的資料夾已存在就匯出失敗」的限制）——這裡把檔案搬回 outputDir，
    // 依段落名稱＋順序重新命名（如 V1.001.png），搬完把已經空了的暫存資料夾刪掉
    static func moveExportedSlides(from exportDir: URL, to outputDir: URL, sectionName: String) throws {
        let fm = FileManager.default
        for (i, file) in KeynoteRunner.exportedImages(in: exportDir).enumerated() {
            let target = outputDir.appendingPathComponent(String(format: "%@.%03d.png", sectionName, i + 1))
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: file, to: target)
        }
        try fm.removeItem(at: exportDir)
    }
}

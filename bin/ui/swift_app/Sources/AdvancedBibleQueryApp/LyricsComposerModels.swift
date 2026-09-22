import Foundation

// SwiftUI 版的歌詞整理工具，對照 web/lyric-composer.html：把混合語言 TXT（例如中英交錯）
// 解析成逐頁對齊的資料、可以手動逐頁修正，最後輸出 ProPresenter TXT 或 main.rb 讀的
// 「Rema 用 TXT」（.r.txt，#! line=/#! placeholders= 包 "# all" ... "# end all"，見
// src/lyrics_parser.rb）。以前這步是開 lyric-composer.html 手動整理完再存檔餵給 bin/main.rb，
// 這裡先把「整理」這段搬進 app，輸出格式跟工作檔 JSON 都刻意跟 html 版對齊，
// 舊的 lyrics-project.json 也能直接在這裡開。

enum LyricLanguage: String, CaseIterable, Codable, Identifiable {
    case cn, en, kr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cn: return "中文 CN"
        case .en: return "英文 EN"
        case .kr: return "韓文 KR"
        }
    }
}

struct LyricRow: Identifiable, Equatable {
    var id = UUID()
    var cn: String = ""
    var en: String = ""
    var kr: String = ""

    subscript(lang: LyricLanguage) -> String {
        get {
            switch lang {
            case .cn: return cn
            case .en: return en
            case .kr: return kr
            }
        }
        set {
            switch lang {
            case .cn: cn = newValue
            case .en: en = newValue
            case .kr: kr = newValue
            }
        }
    }
}

// 混合來源檔的語言順序（每頁固定幾行）。custom 讓使用者自己指定三個下拉選單。
enum MixedFormatPreset: String, CaseIterable, Identifiable {
    case ce, ck, ec, kc, cek, cke, custom

    var id: String { rawValue }

    var order: [LyricLanguage?] {
        switch self {
        case .ce: return [.cn, .en, nil]
        case .ck: return [.cn, .kr, nil]
        case .ec: return [.en, .cn, nil]
        case .kc: return [.kr, .cn, nil]
        case .cek: return [.cn, .en, .kr]
        case .cke: return [.cn, .kr, .en]
        case .custom: return []
        }
    }

    var label: String {
        switch self {
        case .ce: return "CE：中文／英文"
        case .ck: return "CK：中文／韓文"
        case .ec: return "EC：英文／中文"
        case .kc: return "KC：韓文／中文"
        case .cek: return "CEK：中文／英文／韓文"
        case .cke: return "CKE：中文／韓文／英文"
        case .custom: return "自訂順序"
        }
    }
}

// 輸出區用的快速預設（跟 section 1 的混合來源格式是分開的兩組概念）。
enum OutputPreset: String, CaseIterable, Identifiable {
    case c, ce, ck, cek

    var id: String { rawValue }

    var order: [LyricLanguage?] {
        switch self {
        case .c: return [.cn, nil, nil]
        case .ce: return [.cn, .en, nil]
        case .ck: return [.cn, .kr, nil]
        case .cek: return [.cn, .en, .kr]
        }
    }

    var code: String {
        switch self {
        case .c: return "C"
        case .ce: return "CE"
        case .ck: return "CK"
        case .cek: return "CEK"
        }
    }
}

enum LyricsOutputType: String, CaseIterable, Identifiable {
    case propresenter, wrapped

    var id: String { rawValue }
    var label: String { self == .propresenter ? "ProPresenter TXT" : "Rema 用 TXT" }
}

enum EmptyTranslationMode: String, CaseIterable, Identifiable {
    case skip, keep, mark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .skip: return "略過空白語言行"
        case .keep: return "保留空白行"
        case .mark: return "標示 [缺少翻譯]"
        }
    }
}

enum LyricsLineEnding: String, CaseIterable, Identifiable {
    case lf, crlf

    var id: String { rawValue }
    var label: String { self == .lf ? "LF（Mac／一般）" : "CRLF" }
}

struct LyricsOutput {
    var text: String
    var slideCount: Int
}

extension String {
    // JS 的 trimEnd()：只砍尾端空白，保留開頭縮排（歌詞極少需要，但照原本行為做）
    func trimmingTrailingWhitespace() -> String {
        var view = Substring(self)
        while let last = view.last, last.isWhitespace {
            view.removeLast()
        }
        return String(view)
    }
}

final class LyricsComposerStore: ObservableObject {
    // Section 1：解析混合語言 TXT
    @Published var mixedSourceText: String = ""
    @Published var mixedFormat: MixedFormatPreset = .ce {
        didSet { syncMixedOrder() }
    }
    @Published var mixedLang1: LyricLanguage? = .cn
    @Published var mixedLang2: LyricLanguage? = .en
    @Published var mixedLang3: LyricLanguage?
    @Published var parseStatus: String = "尚未解析混合語言檔案。"

    // Section 2：單語歌詞
    @Published var srcCN: String = ""
    @Published var srcEN: String = ""
    @Published var srcKR: String = ""

    // Section 3：逐頁對齊資料
    @Published var rows: [LyricRow] = []
    @Published var status: String = "尚未建立對齊資料。"

    // Section 4：輸出設定
    @Published var lang1: LyricLanguage? = .cn
    @Published var lang2: LyricLanguage? = .en
    @Published var lang3: LyricLanguage?
    @Published var outputType: LyricsOutputType = .propresenter
    @Published var emptyMode: EmptyTranslationMode = .skip
    @Published var filename: String = "lyrics_CE.txt"
    @Published var lineEnding: LyricsLineEnding = .lf

    init() {
        syncMixedOrder()
    }

    // MARK: - Section 1

    func syncMixedOrder() {
        guard mixedFormat != .custom else { return }
        let order = mixedFormat.order
        mixedLang1 = order.count > 0 ? order[0] : nil
        mixedLang2 = order.count > 1 ? order[1] : nil
        mixedLang3 = order.count > 2 ? order[2] : nil
    }

    func parseMixed() {
        let raw = mixedSourceText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            parseStatus = "請先匯入或貼上混合語言 TXT"
            return
        }
        let langs = [mixedLang1, mixedLang2, mixedLang3].compactMap { $0 }
        guard !langs.isEmpty else {
            parseStatus = "請至少選一個語言"
            return
        }
        guard Set(langs).count == langs.count else {
            parseStatus = "來源語言順序不可重複"
            return
        }

        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var parsed: [LyricRow] = []
        var incomplete = 0
        var i = 0
        while i < lines.count {
            let group = Array(lines[i..<min(i + langs.count, lines.count)])
            var row = LyricRow()
            for (j, lang) in langs.enumerated() {
                row[lang] = j < group.count ? group[j] : ""
            }
            if group.count < langs.count { incomplete += 1 }
            parsed.append(row)
            i += langs.count
        }

        rows = parsed
        status = "已由混合語言檔建立 \(rows.count) 頁。"
        parseStatus = "解析完成：\(rows.count) 頁；\(langs.count) 種語言。"
            + (incomplete > 0 ? " 最後一組行數不足，請檢查。" : "")
    }

    var splitCN: String { rows.map(\.cn).filter { !$0.isEmpty }.joined(separator: "\n") }
    var splitEN: String { rows.map(\.en).filter { !$0.isEmpty }.joined(separator: "\n") }
    var splitKR: String { rows.map(\.kr).filter { !$0.isEmpty }.joined(separator: "\n") }

    func sendSplitToSingle() {
        srcCN = splitCN
        srcEN = splitEN
        srcKR = splitKR
    }

    // MARK: - Section 2 / 3

    func buildRows() {
        func normalize(_ text: String) -> [String] {
            text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let cn = normalize(srcCN)
        let en = normalize(srcEN)
        let kr = normalize(srcKR)
        let n = max(cn.count, en.count, kr.count)
        rows = (0..<n).map { i in
            LyricRow(
                cn: i < cn.count ? cn[i] : "",
                en: i < en.count ? en[i] : "",
                kr: i < kr.count ? kr[i] : "")
        }
        status = "已建立 \(n) 頁。CN \(cn.count) 行／EN \(en.count) 行／KR \(kr.count) 行。"
    }

    func addRow() { rows.append(LyricRow()) }
    func deleteRow(id: UUID) { rows.removeAll { $0.id == id } }

    // MARK: - Section 4 / 5

    func applyOutputPreset(_ preset: OutputPreset) {
        let order = preset.order
        lang1 = order[0]; lang2 = order[1]; lang3 = order[2]
        filename = "lyrics_\(preset.code).txt"
    }

    var selectedOutputLangs: [LyricLanguage] { [lang1, lang2, lang3].compactMap { $0 } }

    private func baseSlides() -> [[String]] {
        let langs = selectedOutputLangs
        let slides = rows.map { row -> [String] in
            var lines: [String] = []
            for lang in langs {
                let value = row[lang].trimmingTrailingWhitespace()
                if !value.isEmpty {
                    lines.append(value)
                } else if emptyMode == .keep {
                    lines.append("")
                } else if emptyMode == .mark {
                    lines.append("[缺少翻譯]")
                }
            }
            return lines
        }
        return slides.filter { !$0.isEmpty || emptyMode == .keep }
    }

    func getOutput() -> LyricsOutput {
        let langs = selectedOutputLangs
        let slides = baseSlides()
        var out: String
        if outputType == .wrapped {
            let body = slides.flatMap { $0 }.joined(separator: "\n")
            out = "#! line= \(langs.count)\n#! placeholders= \(langs.map(\.rawValue).joined(separator: ","))\n# all\n\(body)\n# end all"
        } else {
            out = slides.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
        }
        if lineEnding == .crlf {
            out = out.replacingOccurrences(of: "\n", with: "\r\n")
        }
        return LyricsOutput(text: out, slideCount: slides.count)
    }

    // MARK: - 工作檔 JSON（跟 web/lyric-composer.html 的 saveProject()/loadProject() 同一個格式，
    // 兩邊存的檔案可以互開）

    private struct ProjectRow: Codable {
        var cn: String
        var en: String
        var kr: String
    }

    private struct ProjectSettings: Codable {
        var lang1: String
        var lang2: String
        var lang3: String
        var outputType: String
        var emptyMode: String
        var filename: String
        var lineEnding: String
    }

    private struct ProjectFile: Codable {
        var version: Int
        var data: [ProjectRow]
        var settings: ProjectSettings
    }

    func exportProjectJSON() throws -> Data {
        let file = ProjectFile(
            version: 4,
            data: rows.map { ProjectRow(cn: $0.cn, en: $0.en, kr: $0.kr) },
            settings: ProjectSettings(
                lang1: lang1?.rawValue ?? "",
                lang2: lang2?.rawValue ?? "",
                lang3: lang3?.rawValue ?? "",
                outputType: outputType.rawValue,
                emptyMode: emptyMode.rawValue,
                filename: filename,
                lineEnding: lineEnding.rawValue
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    func loadProjectJSON(_ data: Data) throws {
        let file = try JSONDecoder().decode(ProjectFile.self, from: data)
        rows = file.data.map { LyricRow(cn: $0.cn, en: $0.en, kr: $0.kr) }
        lang1 = LyricLanguage(rawValue: file.settings.lang1)
        lang2 = LyricLanguage(rawValue: file.settings.lang2)
        lang3 = LyricLanguage(rawValue: file.settings.lang3)
        outputType = LyricsOutputType(rawValue: file.settings.outputType) ?? .propresenter
        emptyMode = EmptyTranslationMode(rawValue: file.settings.emptyMode) ?? .skip
        filename = file.settings.filename
        lineEnding = LyricsLineEnding(rawValue: file.settings.lineEnding) ?? .lf
        status = "已載入工作檔，共 \(rows.count) 頁。"
    }
}

import Foundation

// 讀本機 bible_src（https://github.com/michaelchanwahyan/bible_src 的 clone）裡的純文字聖經，
// 對照原本的 src/service/github_micheal_chan_bible.s.rb。
// 檔案格式是一行一節：「1.3 神說：...」（章.節 空白 經文），檔名是三字母書卷縮寫（Gen.txt）
public struct LocalBibleService: BibleService {
    public let name = "GithubMichaelChanBible"
    public let translation: String
    public let sourceDirectory: URL

    public init(translation: String = "cuv2", sourceDirectory: URL = RemaPaths.bibleSource) {
        self.translation = translation
        self.sourceDirectory = sourceDirectory
    }

    public static func cloneCommand(into destination: URL = RemaPaths.bibleSource) -> String {
        "git clone --depth 1 https://github.com/michaelchanwahyan/bible_src.git \"\(destination.path)\""
    }

    public func query(_ query: SearchDsl.Query) async throws -> [BibleVerse] {
        guard FileManager.default.fileExists(atPath: sourceDirectory.path) else {
            throw RemaError("找不到本機聖經資料夾 \(sourceDirectory.path)，請重新執行 install.command，或在終端機執行：\(Self.cloneCommand(into: sourceDirectory))")
        }

        var cache: [String: [String]] = [:]
        return query.refs.flatMap { ref -> [BibleVerse] in
            guard let stem = Self.fileStem(bookCode: ref.book) else { return [] }
            if cache[stem] == nil {
                let file = sourceDirectory.appendingPathComponent(translation).appendingPathComponent("\(stem).txt")
                let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                cache[stem] = content.components(separatedBy: .newlines)
            }

            let prefix = "\(ref.chapter)."
            return cache[stem]!.compactMap { line in
                guard line.hasPrefix(prefix), let verse = Self.parseLine(line, book: ref.book) else { return nil }
                if let list = ref.verses, !SearchDsl.verse(verse.verse, isIn: list) { return nil }
                return verse
            }
        }
    }

    // "Genesis" → "Gen"（取最後一個 ASCII 縮寫，截前 3 字元）
    static func fileStem(bookCode: String) -> String? {
        guard let book = Bible.book(code: bookCode),
              let ascii = book.acronyms.last(where: { $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } })
        else { return nil }
        return String(ascii.prefix(3))
    }

    // "1.3 神說：..." → 第 1 章第 3 節
    static func parseLine(_ line: String, book: String) -> BibleVerse? {
        let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2 else { return nil }
        let ref = parts[0].split(separator: ".")
        guard ref.count == 2, let chapter = Int(ref[0]), let verse = Int(ref[1]) else { return nil }
        let text = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return BibleVerse(book: book, chapter: chapter, verse: verse, text: text)
    }
}

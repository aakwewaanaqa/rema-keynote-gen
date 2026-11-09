import Foundation

// 經文來自 biblegateway.com，version 換成 NKJV/KJV 就是同一支爬蟲查其他英文譯本，
// 對照原本的 src/service/bible_gateway_service.s.rb
public struct BibleGatewayService: BibleService {
    public let version: String
    public var name: String { version == "NIV" ? "BibleGatewayService" : "BibleGatewayService\(version)" }

    public init(version: String = "NIV") {
        self.version = version
    }

    static let bookAcronyms: [String: String] = [
        "Genesis": "Gen", "Exodus": "Exod", "Leviticus": "Lev", "Numbers": "Num", "Deuteronomy": "Deut",
        "Joshua": "Josh", "Judges": "Judg", "Ruth": "Ruth", "1Samuel": "1Sam", "2Samuel": "2Sam",
        "1Kings": "1Kgs", "2Kings": "2Kgs", "1Chronicles": "1Chron", "2Chronicles": "2Chron",
        "Ezra": "Ezra", "Nehemiah": "Neh", "Esther": "Est", "Job": "Job", "Psalm": "Ps", "Proverbs": "Prov",
        "Ecclesiastes": "Eccl", "SongOfSongs": "Song", "Isaiah": "Isa", "Jeremiah": "Jer",
        "Lamentations": "Lam", "Ezekiel": "Ezek", "Daniel": "Dan", "Hosea": "Hos", "Joel": "Joel",
        "Amos": "Amos", "Obadiah": "Obad", "Jonah": "Jonah", "Micah": "Mic", "Nahum": "Nah",
        "Habakkuk": "Hab", "Zephaniah": "Zeph", "Haggai": "Hag", "Zechariah": "Zech", "Malachi": "Mal",
        "Matthew": "Matt", "Mark": "Mark", "Luke": "Luke", "John": "John", "Acts": "Acts", "Romans": "Rom",
        "1Corinthians": "1Cor", "2Corinthians": "2Cor", "Galatians": "Gal", "Ephesians": "Eph",
        "Philippians": "Phil", "Colossians": "Col", "1Thessalonians": "1Thess", "2Thessalonians": "2Thess",
        "1Timothy": "1Tim", "2Timothy": "2Tim", "Titus": "Titus", "Philemon": "Philem", "Hebrews": "Heb",
        "James": "James", "1Peter": "1Pet", "2Peter": "2Pet", "1John": "1John", "2John": "2John",
        "3John": "3John", "Jude": "Jude", "Revelation": "Rev",
    ]

    public func query(_ query: SearchDsl.Query) async throws -> [BibleVerse] {
        var result: [BibleVerse] = []
        for ref in query.refs {
            let verses = try await fetchChapter(book: ref.book, chapter: ref.chapter)
            result += filter(verses, by: ref)
        }
        return result
    }

    func fetchChapter(book: String, chapter: Int) async throws -> [BibleVerse] {
        guard let acronym = Self.bookAcronyms[book] else { throw RemaError("Unknown book: \(book)") }

        let url = HTTPFetcher.url("https://www.biblegateway.com/passage/", query: [
            ("search", "\(acronym)\(chapter)"),
            ("version", version),
        ])
        let data = try await HTTPFetcher.get(url)
        guard let doc = HTMLDocument(data: data, encoding: "UTF-8"),
              let container = doc.nodes("//div[\(xpathHasClass("passage-text"))]").first
        else {
            throw RemaError("BibleGateway page structure changed")
        }

        // 標題、交叉引用、註腳、節號、章號都不是經文本身
        let noise = ".//h3 | .//sup[\(xpathHasClass("crossreference"))] | .//sup[\(xpathHasClass("footnote"))]"
            + " | .//sup[\(xpathHasClass("versenum"))] | .//span[\(xpathHasClass("chapternum"))]"
        container.nodes(noise).forEach { $0.remove() }

        // 按照 verse class（如 "Matt-18-18"）分組，詩篇這類分行排版一節會有多個 span
        let versePattern = try! NSRegularExpression(pattern: #"\w+-\d+-(\d+)"#)
        var verseMap: [Int: [String]] = [:]
        for span in container.nodes(".//span[\(xpathHasClass("text"))]") {
            let classes = span.attribute("class") ?? ""
            guard let match = versePattern.firstMatch(in: classes, range: NSRange(classes.startIndex..., in: classes)),
                  let range = Range(match.range(at: 1), in: classes),
                  let verseNum = Int(classes[range])
            else { continue }

            let text = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            verseMap[verseNum, default: []].append(text)
        }

        return verseMap.keys.sorted().map { verseNum in
            BibleVerse(book: book, chapter: chapter, verse: verseNum, text: verseMap[verseNum]!.joined(separator: " "))
        }
    }
}

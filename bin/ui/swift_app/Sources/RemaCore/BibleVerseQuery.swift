import Foundation

// 同一節經文、單一譯本的內容。service 是來源 token（fhl/niv/nkjv/gae/local），
// translation 是給人看的來源名稱（信望愛 CUV/NIV/...）。book 會跟著這個譯本的語言變
// （中文譯本顯示中文書名、NIV/NKJV 顯示英文書名、개역개정 顯示韓文書名），所以放在這裡而不是外層。
public struct VerseTranslation: Codable, Hashable, Sendable {
    public var service: String
    public var translation: String
    public var book: String
    public var content: String

    public init(service: String, translation: String, book: String, content: String) {
        self.service = service
        self.translation = translation
        self.book = book
        self.content = content
    }
}

// 同一節經文，底下疊多個譯本——一節一個 item，不是一節×一譯本一個 item
public struct QueriedVerseGroup: Codable, Hashable, Sendable {
    public var chapter: Int
    public var verse: Int
    public var translations: [VerseTranslation]

    public init(chapter: Int, verse: Int, translations: [VerseTranslation]) {
        self.chapter = chapter
        self.verse = verse
        self.translations = translations
    }
}

// 查經文給 App 預覽用，對照原本的 bin/ui/swift_app/advanced_bible_query_cli.rb。
// 只負責查詢；{token} 範本代換是「產生 Keynote」那一步的事（見 BibleKeynoteGenerator）
public enum BibleVerseQuery {
    public struct Outcome: Sendable {
        public let status: String
        public let verses: [QueriedVerseGroup]
        // 各查詢來源自己掛掉的錯誤（例如某個聖經網站故障），跟 status 分開回傳——
        // 這種診斷內容可能很長，App 要用可捲動/可複製的彈窗顯示
        public let sourceErrors: [String]
    }

    public static func run(_ rawText: String, sources: Set<BibleSource>) async throws -> Outcome {
        guard !rawText.isEmpty else { throw RemaError("缺少查詢字串") }
        guard !sources.isEmpty else {
            let available = BibleSource.allCases.map(\.token).joined(separator: "/")
            return Outcome(status: "請至少勾選一個查詢來源（可用: \(available)）", verses: [], sourceErrors: [])
        }

        let outcome = try await BibleQuery.run(rawText, sources: BibleSource.querySources(enabled: sources))
        return Outcome(
            status: "共 \(outcome.entries.count) 節，已取得經文",
            verses: groups(from: outcome.entries),
            sourceErrors: outcome.sourceErrors
        )
    }

    static func groups(from entries: [BibleQueryEntry]) -> [QueriedVerseGroup] {
        entries.compactMap { entry in
            let book = Bible.book(code: entry.book)
            let translations = zip(BibleSource.allCases, entry.texts).compactMap { source, text -> VerseTranslation? in
                guard !text.isEmpty else { return nil }
                return VerseTranslation(
                    service: source.token,
                    translation: source.translationName,
                    book: book.map(source.bookName) ?? entry.book,
                    content: text
                )
            }
            guard !translations.isEmpty else { return nil }
            return QueriedVerseGroup(chapter: entry.chapter, verse: entry.verse, translations: translations)
        }
    }
}

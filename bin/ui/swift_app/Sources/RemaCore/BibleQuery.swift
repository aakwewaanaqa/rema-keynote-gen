import Foundation

// 各來源查到的一節經文，對照原本的 src/service/bible_query_verse.rb
public struct BibleVerse: Equatable, Sendable {
    public let book: String  // Bible.books 的 code
    public let chapter: Int
    public let verse: Int
    public let text: String

    public init(book: String, chapter: Int, verse: Int, text: String) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.text = text
    }
}

public protocol BibleService: Sendable {
    // 錯誤訊息前綴用，例如「SpringBibleService: ...」
    var name: String { get }
    func query(_ query: SearchDsl.Query) async throws -> [BibleVerse]
}

extension BibleService {
    // 抓整章、再依 ref.verses 篩節——網路來源都是一次抓一整章
    func filter(_ verses: [BibleVerse], by ref: SearchDsl.BibleRef) -> [BibleVerse] {
        guard let list = ref.verses else { return verses }
        return verses.filter { SearchDsl.verse($0.verse, isIn: list) }
    }
}

public struct RemaError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

// 同一節經文、各來源的內容；texts 的順序跟傳入 BibleQuery.run 的 sources 一致，沒查到的是空字串
public struct BibleQueryEntry: Equatable, Sendable {
    public let book: String
    public let chapter: Int
    public let verse: Int
    public let texts: [String]

    public init(book: String, chapter: Int, verse: Int, texts: [String]) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.texts = texts
    }

    // 錯誤訊息裡標示是哪一節用，例如「使徒行傳6:1」
    public var location: String {
        "\(Bible.book(code: book)?.chinese ?? book)\(chapter):\(verse)"
    }
}

public struct BibleQueryOutcome: Sendable {
    public let entries: [BibleQueryEntry]
    // 個別來源掛掉（例如外部網站故障）的錯誤，不影響其他來源的結果
    public let sourceErrors: [String]
}

// 對照原本的 src/domain/bible_query.rb
public enum BibleQuery {
    // sources 是 [(要不要查, service)]。各來源同時查（以前 Ruby 版是一個查完才查下一個），
    // 個別來源掛掉只記錄錯誤，不讓其他已勾選的來源也查不到。
    // 呼叫端的 Task 被取消時，進行中的網路請求會跟著取消，最後丟出 CancellationError
    public static func run(_ rawText: String, sources: [(enabled: Bool, service: any BibleService)]) async throws -> BibleQueryOutcome {
        let query = SearchDsl.parse(rawText)

        let results = await withTaskGroup(of: (Int, Result<[BibleVerse], Error>).self) { group in
            for (idx, source) in sources.enumerated() where source.enabled {
                group.addTask {
                    do {
                        return (idx, .success(try await source.service.query(query)))
                    } catch {
                        return (idx, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<[BibleVerse], Error>)] = []
            for await item in group { collected.append(item) }
            return collected.sorted { $0.0 < $1.0 }
        }
        try Task.checkCancellation()

        // 同一節經文，各語言來源合併成同一筆；key 用 書卷/章/節 而不是只用節，
        // 避免查詢橫跨多卷書時節號互相覆蓋
        struct Key: Hashable { let book: String; let chapter: Int; let verse: Int }
        var grouped: [Key: [String]] = [:]
        var sourceErrors: [String] = []

        for (idx, result) in results {
            switch result {
            case .success(let verses):
                for v in verses {
                    let key = Key(book: v.book, chapter: v.chapter, verse: v.verse)
                    grouped[key, default: Array(repeating: "", count: sources.count)][idx] = v.text
                }
            case .failure(let error):
                sourceErrors.append("\(sources[idx].service.name): \(error.localizedDescription)")
            }
        }

        let entries = grouped
            .map { BibleQueryEntry(book: $0.key.book, chapter: $0.key.chapter, verse: $0.key.verse, texts: $0.value) }
            .sorted {
                let a = (Bible.index(code: $0.book) ?? 0, $0.chapter, $0.verse)
                let b = (Bible.index(code: $1.book) ?? 0, $1.chapter, $1.verse)
                return a < b
            }

        return BibleQueryOutcome(entries: entries, sourceErrors: sourceErrors)
    }
}

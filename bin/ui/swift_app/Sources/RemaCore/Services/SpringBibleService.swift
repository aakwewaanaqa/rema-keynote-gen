import Foundation

// 經文來自 springbible.fhl.net（信望愛，和合本），對照原本的 src/service/spring_bible.s.rb
public struct SpringBibleService: BibleService {
    public let name = "SpringBibleService"

    public init() {}

    public func query(_ query: SearchDsl.Query) async throws -> [BibleVerse] {
        var result: [BibleVerse] = []
        for ref in query.refs {
            let verses = try await fetchChapter(book: ref.book, chapter: ref.chapter)
            result += filter(verses, by: ref)
        }
        return result
    }

    func fetchChapter(book: String, chapter: Int) async throws -> [BibleVerse] {
        let url = HTTPFetcher.url("https://springbible.fhl.net/Bible2/cgic201/read201.cgi", query: [
            ("na", "0"),
            ("chap", String(Bible.pureChapterIndex(code: book, chapter: chapter))),
            ("ver", "big5"),
            ("ft", "0"),
            ("temp", "-1"),
            ("tight", "1"),
        ])
        let data = try await HTTPFetcher.get(url, attempts: 3)
        // 舊版和合本頁面是 Big5 編碼
        guard let doc = HTMLDocument(data: data, encoding: "BIG5") else {
            throw RemaError("無法解析信望愛頁面")
        }
        // 每一節是一個 <li>，節號沒有另外標示，就是 li 的順序
        return doc.nodes("//body//div//ol/li").enumerated().map { i, li in
            BibleVerse(book: book, chapter: chapter, verse: i + 1,
                       text: li.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

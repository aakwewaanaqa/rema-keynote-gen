import Foundation

// 經文來自 holybible.or.kr（개역개정 韓文改譯版），對照原本的 src/service/holy_bible_korean_service.s.rb。
// 這個站只有 http，App 的 Info.plist 有針對這個網域開 ATS 例外
public struct HolyBibleKoreanService: BibleService {
    public let name = "HolyBibleKoreanService"

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
        // VL 是 1-based 書卷序號，創世記到啟示錄順序跟 Bible.books 一致
        guard let index = Bible.index(code: book) else { throw RemaError("Unknown book: \(book)") }

        let url = HTTPFetcher.url("http://www.holybible.or.kr/mobile/B_GAE/cgi/bibleftxt.php", query: [
            ("VR", "GAE"),
            ("VL", String(index + 1)),
            ("CN", String(chapter)),
            ("CV", "99"),
        ])
        let data = try await HTTPFetcher.get(url)
        guard let doc = HTMLDocument(data: data, encoding: "EUC-KR") else {
            throw RemaError("無法解析 holybible.or.kr 頁面")
        }

        // 每段經文包在 <ol start="NNN" id="b_NNN"> 裡，節號沒有另外標示，
        // 是用 ol 的 start 屬性加上 li 在裡面的順序推算出來的
        let ols = doc.nodes("//ol[starts-with(@id, 'b_')]")

        // holybible.or.kr 常常自己內部 include 經文用的 bibl_ftxt.php 失敗（回應裡夾雜 "Connection refused"），
        // 外層頁面照樣回 200，但完全沒有經文區塊——這種情況不要默默回傳空陣列，
        // 不然呼叫端只會覺得「這節沒有韓文翻譯」，看不出是原站掛了
        guard !ols.isEmpty else { throw RemaError("holybible.or.kr 韓文來源目前無法取得經文（原站可能故障）") }

        return ols.flatMap { ol -> [BibleVerse] in
            let start = Int(ol.attribute("start") ?? "") ?? 1
            return ol.nodes(".//li").enumerated().map { i, li in
                BibleVerse(book: book, chapter: chapter, verse: start + i,
                           text: li.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}

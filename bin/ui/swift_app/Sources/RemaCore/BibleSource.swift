import Foundation

// 可以勾選的查詢來源。宣告順序就是 BibleQueryEntry.texts 的索引順序（範本代換靠這個對到經文），
// 不要隨便調換或從中間插入
public enum BibleSource: String, CaseIterable, Sendable {
    case local  // 麥可陳（本機 bible_src 的 cuv2）
    case fhl    // 信望愛聖經資源中心（和合本）
    case niv    // BibleGateway（NIV）
    case gae    // holybible.or.kr（개역개정）
    case nkjv   // BibleGateway（NKJV）
    case kjv    // BibleGateway（KJV）

    public var token: String { rawValue }

    public var service: any BibleService {
        switch self {
        case .local: return LocalBibleService()
        case .fhl: return SpringBibleService()
        case .niv: return BibleGatewayService(version: "NIV")
        case .gae: return HolyBibleKoreanService()
        case .nkjv: return BibleGatewayService(version: "NKJV")
        case .kjv: return BibleGatewayService(version: "KJV")
        }
    }

    // 給人看的來源名稱
    public var translationName: String {
        switch self {
        case .local: return "麥可陳"
        case .fhl: return "信望愛 CUV"
        case .niv: return "NIV"
        case .gae: return "개역개정"
        case .nkjv: return "NKJV"
        case .kjv: return "KJV"
        }
    }

    // 書卷名要跟著該譯本的語言變，不是每個譯本都硬塞中文書名
    public func bookName(_ book: BibleBook) -> String {
        switch self {
        case .local, .fhl: return book.chinese
        case .niv, .nkjv, .kjv: return book.english
        case .gae: return book.korean
        }
    }

    // 把勾選的來源轉成 BibleQuery.run 要的格式：每個來源都在、只是標記要不要查，
    // 這樣 texts 的索引才會固定對到同一個來源
    public static func querySources(enabled: Set<BibleSource>) -> [(enabled: Bool, service: any BibleService)] {
        allCases.map { (enabled.contains($0), $0.service) }
    }

    // "fhl,niv" → [.fhl, .niv]，不認得的 token 忽略
    public static func parse(tokens: String) -> Set<BibleSource> {
        Set(tokens.split(separator: ",").compactMap { BibleSource(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    }
}

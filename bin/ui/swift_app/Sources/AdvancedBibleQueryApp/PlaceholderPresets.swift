import Foundation

// Keynote 投影片可用的 placeholder；format 用 {token}，實際代換規則對照
// src/domain/bible_template.rb 開頭的註解：
// {中}/{英}/{英王}/{新英王}/{韓} - 經文內容　{中書}/{英書}/{韓書} - 書名　{章}/{節} - 章節
struct KeynotePlaceholder: Identifiable, Hashable {
    var id: UUID = UUID()
    var placeholder: String
    var format: String
}

// 每種譯本都是獨立的語言，有勾就出現、沒勾就不出現，彼此不互斥
// （niv/nkjv/kjv 都算英文，但各自獨立，不是同一個「英文欄位」的三個選項）。
enum TranslationLanguage {
    case cuv, niv, nkjv, kjv, gae

    var textToken: String {
        switch self {
        case .cuv: return "中"
        case .niv: return "英"
        case .nkjv: return "新英王"
        case .kjv: return "英王"
        case .gae: return "韓"
        }
    }
    var textLabel: String {
        switch self {
        case .cuv: return "cuv"
        case .niv: return "niv"
        case .nkjv: return "nkjv"
        case .kjv: return "kjv"
        case .gae: return "kr"
        }
    }
    // 書名依「語言」分組，不是依「譯本」分組：niv/nkjv/kjv 都是英文書名，共用 {英書}，
    // 不會因為同時開 niv+kjv 就出現兩次英文書名 placeholder。
    var bookToken: String {
        switch self {
        case .cuv: return "{中書}"
        case .niv, .nkjv, .kjv: return "{英書}"
        case .gae: return "{韓書}"
        }
    }
    var bookLabel: String {
        switch self {
        case .cuv: return "book c"
        case .niv, .nkjv, .kjv: return "book e"
        case .gae: return "book k"
        }
    }
}

// 書名／章節怎麼排版。「書名拆開＋章節合併」邏輯上講不通（合併要塞進拆開後的哪一格？），所以不列。
enum PlaceholderLayout {
    case allMerged                // 書名＋章節全部塞進同一格
    case bookMergedRangeSeparate  // 書名合併一格，章節獨立一格
    case bookSplitRangeSeparate   // 書名依語言拆開，章節獨立一格
}

extension KeynotePlaceholder {
    // languages 是目前有勾選的譯本（順序建議固定，輸出才穩定）。
    static func preset(languages: [TranslationLanguage], layout: PlaceholderLayout) -> [KeynotePlaceholder] {
        var items = languages.map { lang in
            KeynotePlaceholder(placeholder: "\(lang.textLabel) text", format: "{\(lang.textToken)}")
        }

        // 書名按語言去重：niv/nkjv/kjv 同時開的話只留一個 {英書}
        var seenBookTokens = Set<String>()
        let bookEntries = languages.compactMap { lang -> (label: String, token: String)? in
            guard seenBookTokens.insert(lang.bookToken).inserted else { return nil }
            return (lang.bookLabel, lang.bookToken)
        }

        switch layout {
        case .allMerged:
            let ref = (bookEntries.map(\.token) + ["{章}:{節}"]).joined(separator: " ")
            items.append(KeynotePlaceholder(placeholder: "ref", format: ref))
        case .bookMergedRangeSeparate:
            items.append(KeynotePlaceholder(placeholder: "book", format: bookEntries.map(\.token).joined(separator: " ")))
            items.append(KeynotePlaceholder(placeholder: "range", format: "{章}:{節}"))
        case .bookSplitRangeSeparate:
            for entry in bookEntries {
                items.append(KeynotePlaceholder(placeholder: entry.label, format: entry.token))
            }
            items.append(KeynotePlaceholder(placeholder: "range", format: "{章}:{節}"))
        }
        return items
    }
}

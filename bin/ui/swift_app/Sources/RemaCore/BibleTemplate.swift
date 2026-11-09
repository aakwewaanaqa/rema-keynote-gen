import Foundation

// placeholder 範本代換，對照原本的 src/domain/bible_template.rb。
// 以下列出 {token} 之所對應的內容
// {中}/{cuv}       - 信望愛經節內容
// {英}/{niv}       - Biblegateway NIV 經節內容
// {英王}/{kjv}     - Biblegateway KJV 經節內容
// {新英王}/{nkjv}  - Biblegateway NKJV 經節內容
// {韓}/{gae}       - Holynet 개역개장 經節內容
// {local}          - 麥可陳（本機 cuv2）經節內容
// {中書}/{cb} - 中文書名
// {英書}/{eb} - 英文書名
// {韓書}/{kb} - 韓文書名
// {章}/{ch}   - 章次
// {節}/{vr}   - 節次
public enum BibleTemplate {
    // 不查經文來源、而是從節資訊本身算出來的 token
    static let computedTokens: Set<String> = ["verse", "chapter", "book_c", "book_e", "book_k"]

    // 好記的別名 -> 實際 token。{中}/{cuv} 對到信望愛(fhl)，不是 local，
    // 因為使用者習慣把「中文」跟信望愛的和合本聯想在一起，跟 local 的 cuv2 是兩回事
    static let aliases: [String: String] = [
        "中": "fhl",
        "cuv": "fhl",
        "英": "niv",
        "韓": "gae",
        "英王": "kjv",    // King James
        "新英王": "nkjv",  // New King James，跟 {英王} 分開避免混淆
        "中書": "book_c",
        "cb": "book_c",
        "英書": "book_e",
        "eb": "book_e",
        "韓書": "book_k",
        "kb": "book_k",
        "章": "chapter",
        "ch": "chapter",
        "節": "verse",
        "vr": "verse",
    ]

    // 把別名代換回實際 token，不是別名就原樣傳回
    public static func canonicalToken(_ token: String) -> String {
        aliases[token] ?? token
    }

    // 把單一 placeholder 的範本內容替換成實際內容。
    // 找不到 token、或 token 對應的來源/資訊拿不到，都算錯誤，記錄到 errors 並在內文標示出來。
    // 範本裡打的字面 \n（反斜線加 n）會換成真的換行
    public static func renderPlaceholder(
        _ body: String, entry: BibleQueryEntry, errors: inout [String], placeholderName: String
    ) -> String {
        let book = Bible.book(code: entry.book)
        let location = entry.location

        // 用「不是大括號的任何字元」來抓 token 名稱，別名（{中}/{章}/{節}...）都是中文
        let pattern = try! NSRegularExpression(pattern: #"\{([^{}]+)\}"#)
        let ns = body as NSString
        var rendered = ""
        var cursor = 0
        for match in pattern.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            rendered += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length

            let rawToken = ns.substring(with: match.range(at: 1))
            let token = canonicalToken(rawToken)
            if let value = resolveToken(token, entry: entry, book: book) {
                rendered += value
                continue
            }

            if BibleSource(rawValue: token) != nil {
                errors.append("\(location) #\(placeholderName)：來源 {\(rawToken)} 沒有經文（可能沒勾選查詢或查無結果）")
            } else if computedTokens.contains(token) {
                errors.append("\(location) #\(placeholderName)：無法取得 {\(rawToken)}（找不到書卷資料）")
            } else {
                errors.append("\(location) #\(placeholderName)：未知的 token {\(rawToken)}")
            }
            rendered += "⚠️{\(rawToken)}"
        }
        rendered += ns.substring(from: cursor)

        return rendered.replacingOccurrences(of: "\\n", with: "\n")
    }

    // token 這裡一律是已經過 canonicalToken 代換過的實際 token，不會再收到別名
    static func resolveToken(_ token: String, entry: BibleQueryEntry, book: BibleBook?) -> String? {
        switch token {
        case "verse": return String(entry.verse)
        case "chapter": return String(entry.chapter)
        case "book_c": return book?.chinese
        case "book_e": return book?.english
        case "book_k": return book?.korean
        default:
            guard let source = BibleSource(rawValue: token),
                  let idx = BibleSource.allCases.firstIndex(of: source),
                  idx < entry.texts.count
            else { return nil }
            let value = entry.texts[idx]
            return value.isEmpty ? nil : value
        }
    }
}

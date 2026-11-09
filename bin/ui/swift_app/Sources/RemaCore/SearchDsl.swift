import Foundation

// 聖經查詢字串（如「太1:1-5,7;創3:7」）的 tokenizer 與 parser，對照原本的
// src/domain/search_dsl/tokenize.rb 與 ast.rb。
//
// 解析結果是一棵只有三層的樹：
//   Query                          ← 整個查詢（可能包含多個書卷）
//     └─ [BibleRef, BibleRef ...]  ← 每個書卷+章的查詢單元
//          └─ [single | range ...] ← 該章裡要取的節
//
// 範例：「太1:1-5,7;創3:7」會被解析成：
//
//   Query
//   ├─ BibleRef { book: "Matthew", chapter: 1, verses: [.range(1, 5), .single(7)] }
//   └─ BibleRef { book: "Genesis", chapter: 3, verses: [.single(7)] }
//
// 文法（BNF）：
//   Query         = BibleRefGroup (';' BibleRefGroup)*
//   BibleRefGroup = IDENTIFIER ChapterVerses (',' ChapterVerses)*   ← 展開成多個 BibleRef
//   ChapterVerses = NUMBER (':' VerseList)?
//   VerseList     = VerseItem (',' VerseItem)*
//   VerseItem     = NUMBER ('-' NUMBER)?
//
// BibleRefGroup 的逗號分支只在「逗號後面接著 數字:數字」時才成立（換章），
// 否則逗號屬於 VerseList，代表同一章的下一節，例如「創2:15,3:6」＝ 創2:15 + 創3:6，
// 但「太1:1-5,7」的逗號是同一章多一節，不是換到第 7 章。
public enum SearchDsl {
    public enum TokenKind: Equatable, Sendable {
        case identifier, number, comma, colon, semicolon, hyphen
    }

    public struct Token: Equatable, Sendable {
        public let kind: TokenKind
        public let text: String
    }

    public enum VerseItem: Equatable, Hashable, Sendable {
        case single(Int)
        case range(Int, Int?)  // 結尾為 nil 代表「從這節到章末」（例如「創1:3-」）
    }

    public struct BibleRef: Equatable, Sendable {
        public let book: String          // Bible.books 的 code
        public let chapter: Int
        public let verses: [VerseItem]?  // nil 代表整章
    }

    public struct Query: Equatable, Sendable {
        public let refs: [BibleRef]
    }

    private static let commas: Set<Character> = [",", "，", "、"]
    private static let colons: Set<Character> = [":", "："]
    private static let semicolons: Set<Character> = [";", "；"]
    private static let hyphens: Set<Character> = ["-", "−", "—", "－", "~", "～"]
    // 空格、全形空格、tab 不帶任何意義，純粹是排版習慣（例如「路加福音 19:3-5」），直接跳過
    private static let blanks: Set<Character> = [" ", "\t", "　"]

    private static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    private static func isIdentifierChar(_ c: Character) -> Bool {
        !(isDigit(c) || c.isWhitespace || commas.contains(c) || colons.contains(c)
            || semicolons.contains(c) || hyphens.contains(c))
    }

    public static func tokenize(_ str: String) -> [Token] {
        let chars = Array(str)
        var tokens: [Token] = []
        var i = 0

        // 從 i 開始吃掉連續符合條件的字元，回傳吃到的字串
        func take(while predicate: (Character) -> Bool) -> String {
            let start = i
            while i < chars.count && predicate(chars[i]) { i += 1 }
            return String(chars[start..<i])
        }

        while i < chars.count {
            let c = chars[i]
            if blanks.contains(c) {
                i += 1
            } else if c.isNewline {
                // 換行等同分號：貼上「一行一筆」的查詢（如「啟示錄3:7-8\n使徒行傳5:19」）時，
                // 換行就是使用者拿來分隔不同筆查詢的符號，跟打「;」的意思一樣。
                // 順便吃掉換行後面的空白、空行，避免多留下沒用的 token
                _ = take { $0.isNewline || blanks.contains($0) }
                tokens.append(Token(kind: .semicolon, text: ";"))
            } else if isDigit(c) {
                tokens.append(Token(kind: .number, text: take(while: isDigit)))
            } else if commas.contains(c) {
                i += 1
                tokens.append(Token(kind: .comma, text: ","))
            } else if colons.contains(c) {
                i += 1
                tokens.append(Token(kind: .colon, text: ":"))
            } else if semicolons.contains(c) {
                i += 1
                tokens.append(Token(kind: .semicolon, text: ";"))
            } else if hyphens.contains(c) {
                i += 1
                tokens.append(Token(kind: .hyphen, text: "-"))
            } else if isIdentifierChar(c) {
                tokens.append(Token(kind: .identifier, text: take(while: isIdentifierChar)))
            } else {
                // 其他空白字元（例如垂直定位字元）不帶意義，跳過
                i += 1
            }
        }
        return tokens
    }

    // 節號是否落在 verses 清單（single | range 混合）之中
    public static func verse(_ verse: Int, isIn list: [VerseItem]) -> Bool {
        list.contains { item in
            switch item {
            case .single(let v): return v == verse
            case .range(let from, let to): return verse >= from && (to == nil || verse <= to!)
            }
        }
    }

    // 入口：字串 → Query
    public static func parse(_ str: String) -> Query {
        var parser = Parser(tokens: tokenize(str))
        return parser.parseQuery()
    }

    // 遞迴下降（recursive descent）：每條文法規則對應一個方法，從左到右消耗 token，
    // 符合就推進，不符合就回傳 nil 讓上層決定怎麼處理
    private struct Parser {
        let tokens: [Token]
        var index = 0

        func peek(_ offset: Int = 0) -> TokenKind? {
            let i = index + offset
            return i < tokens.count ? tokens[i].kind : nil
        }

        mutating func advance() -> Token? {
            guard index < tokens.count else { return nil }
            defer { index += 1 }
            return tokens[index]
        }

        // 逗號後面接著「數字 冒號」才代表換章（如 2:15,3:6 的 ',3:6'），
        // 不消耗 token，只是往後看，讓呼叫端決定逗號到底屬於 VerseList 還是換章
        func chapterSwitchAhead() -> Bool {
            peek() == .comma && peek(1) == .number && peek(2) == .colon
        }

        // NUMBER ('-' NUMBER)?
        mutating func parseVerseItem() -> VerseItem? {
            guard peek() == .number, let from = advance().flatMap({ Int($0.text) }) else { return nil }
            guard peek() == .hyphen else { return .single(from) }
            _ = advance()
            if peek() == .number, let to = advance().flatMap({ Int($0.text) }) {
                return .range(from, to)
            }
            return .range(from, nil)
        }

        // VerseItem (',' VerseItem)*
        mutating func parseVerseList() -> [VerseItem]? {
            guard let first = parseVerseItem() else { return nil }
            var items = [first]
            // 逗號後面若是「數字:數字」代表換章，那個逗號要留給 parseBibleRefGroup 處理
            while peek() == .comma && !chapterSwitchAhead() {
                _ = advance()
                if let item = parseVerseItem() { items.append(item) }
            }
            return items
        }

        // NUMBER (':' VerseList)?
        mutating func parseChapterVerses() -> (chapter: Int, verses: [VerseItem]?)? {
            guard peek() == .number, let chapter = advance().flatMap({ Int($0.text) }) else { return nil }
            var verses: [VerseItem]?
            if peek() == .colon {
                _ = advance()
                verses = parseVerseList()
            }
            return (chapter, verses)
        }

        // IDENTIFIER ChapterVerses (',' ChapterVerses)*  →  [BibleRef, ...]
        // 回傳陣列是因為一個書名可以展開成好幾個不同章的 BibleRef（換章逗號的緣故）
        mutating func parseBibleRefGroup() -> [BibleRef] {
            guard peek() == .identifier, let bookToken = advance() else { return [] }
            guard let book = Bible.match(bookToken.text) else { return [] }  // 識別不出書卷就跳過整個 ref
            guard let first = parseChapterVerses() else { return [] }

            var refs = [BibleRef(book: book.code, chapter: first.chapter, verses: first.verses)]
            while chapterSwitchAhead() {
                _ = advance()  // 換章的逗號
                if let cv = parseChapterVerses() {
                    refs.append(BibleRef(book: book.code, chapter: cv.chapter, verses: cv.verses))
                }
            }
            return refs
        }

        // BibleRefGroup (';' BibleRefGroup)*
        mutating func parseQuery() -> Query {
            var refs = parseBibleRefGroup()
            guard !refs.isEmpty else { return Query(refs: []) }
            while peek() == .semicolon {
                _ = advance()
                refs += parseBibleRefGroup()
            }
            return Query(refs: refs)
        }
    }
}

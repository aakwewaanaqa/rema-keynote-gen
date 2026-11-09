import Foundation

// 對照原本的 src/domain/bible.rb（Domain::Bible）
public struct BibleBook: Hashable, Sendable {
    public let max: Int        // 章數
    public let code: String    // 書卷代碼，各來源之間用這個對照，如 "Matthew"
    public let english: String
    public let chinese: String
    public let acronyms: [String]
    public let korean: String
}

public enum Bible {
    public static func book(code: String) -> BibleBook? {
        books.first { $0.code == code }
    }

    // 創世記到啟示錄的 0-based 序號
    public static func index(code: String) -> Int? {
        books.firstIndex { $0.code == code }
    }

    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                curr[j] = a[i - 1] == b[j - 1] ? prev[j - 1] : 1 + Swift.min(prev[j], curr[j - 1], prev[j - 1])
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }

    // 依序比對：代碼、英文全名、中文全名、縮寫、英文全名前綴、縮寫前綴、英文全名編輯距離 <= 2，
    // 第一本符合任一條件的書卷就是結果（跟 Ruby 版 MATCH_CHAPTER 一樣是逐本書檢查全部條件，不是逐條件掃全部書）
    public static func match(_ raw: String) -> BibleBook? {
        let str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = str.lowercased().filter { !$0.isWhitespace }
        guard !normalized.isEmpty else { return nil }

        return books.first { book in
            let en = book.english.lowercased().filter { !$0.isWhitespace }
            return book.code.lowercased() == normalized
                || en == normalized
                || book.chinese == str
                || book.acronyms.contains { $0.lowercased() == normalized }
                || en.hasPrefix(normalized)
                || book.acronyms.contains { $0.lowercased().hasPrefix(normalized) }
                || levenshtein(en, normalized) <= 2
        }
    }

    public static let books: [BibleBook] = [
        BibleBook(max: 50, code: "Genesis", english: "Genesis", chinese: "創世記", acronyms: ["創", "Gen"], korean: "창세기"),
        BibleBook(max: 40, code: "Exodus", english: "Exodus", chinese: "出埃及記", acronyms: ["出", "Exo", "Exod"], korean: "출애굽기"),
        BibleBook(max: 27, code: "Leviticus", english: "Leviticus", chinese: "利未記", acronyms: ["利", "Lev"], korean: "레위기"),
        BibleBook(max: 36, code: "Numbers", english: "Numbers", chinese: "民數記", acronyms: ["民", "Num"], korean: "민수기"),
        BibleBook(max: 34, code: "Deuteronomy", english: "Deuteronomy", chinese: "申命記", acronyms: ["申", "Deut", "Deu"], korean: "신명기"),
        BibleBook(max: 24, code: "Joshua", english: "Joshua", chinese: "約書亞記", acronyms: ["書", "Josh", "Jos"], korean: "여호수아"),
        BibleBook(max: 21, code: "Judges", english: "Judges", chinese: "士師記", acronyms: ["士", "Judg", "Jug"], korean: "사사기"),
        BibleBook(max: 4, code: "Ruth", english: "Ruth", chinese: "路得記", acronyms: ["得", "Ruth", "Rut"], korean: "룻기"),
        BibleBook(max: 31, code: "1Samuel", english: "1 Samuel", chinese: "撒母耳記上", acronyms: ["撒上", "1Sam", "1Sa"], korean: "사무엘상"),
        BibleBook(max: 24, code: "2Samuel", english: "2 Samuel", chinese: "撒母耳記下", acronyms: ["撒下", "2Sam", "2Sa"], korean: "사무엘하"),
        BibleBook(max: 22, code: "1Kings", english: "1 Kings", chinese: "列王紀上", acronyms: ["王上", "1Kgs", "1Ki"], korean: "열왕기상"),
        BibleBook(max: 25, code: "2Kings", english: "2 Kings", chinese: "列王紀下", acronyms: ["王下", "2Kgs", "2Ki"], korean: "열왕기하"),
        BibleBook(max: 29, code: "1Chronicles", english: "1 Chronicles", chinese: "歷代志上", acronyms: ["代上", "1Chron", "1Ch"], korean: "역대상"),
        BibleBook(max: 36, code: "2Chronicles", english: "2 Chronicles", chinese: "歷代志下", acronyms: ["代下", "2Chron", "2Ch"], korean: "역대하"),
        BibleBook(max: 10, code: "Ezra", english: "Ezra", chinese: "以斯拉記", acronyms: ["拉", "Ezra", "Ezr"], korean: "에스라"),
        BibleBook(max: 13, code: "Nehemiah", english: "Nehemiah", chinese: "尼希米記", acronyms: ["尼", "Neh"], korean: "느헤미야"),
        BibleBook(max: 10, code: "Esther", english: "Esther", chinese: "以斯帖記", acronyms: ["斯", "Est"], korean: "에스더"),
        BibleBook(max: 42, code: "Job", english: "Job", chinese: "約伯記", acronyms: ["伯", "Job"], korean: "욥기"),
        BibleBook(max: 150, code: "Psalm", english: "Psalm", chinese: "詩篇", acronyms: ["詩", "Ps", "Psa"], korean: "시편"),
        BibleBook(max: 31, code: "Proverbs", english: "Proverbs", chinese: "箴言", acronyms: ["箴", "Prov", "Pro"], korean: "잠언"),
        BibleBook(max: 12, code: "Ecclesiastes", english: "Ecclesiastes", chinese: "傳道書", acronyms: ["傳", "Ecc", "Eccl"], korean: "전도서"),
        BibleBook(max: 8, code: "SongOfSongs", english: "Song of Songs", chinese: "雅歌", acronyms: ["歌", "Song", "Son"], korean: "아가"),
        BibleBook(max: 66, code: "Isaiah", english: "Isaiah", chinese: "以賽亞書", acronyms: ["賽", "Isa"], korean: "이사야"),
        BibleBook(max: 52, code: "Jeremiah", english: "Jeremiah", chinese: "耶利米書", acronyms: ["耶", "Jer"], korean: "예레미야"),
        BibleBook(max: 5, code: "Lamentations", english: "Lamentations", chinese: "耶利米哀歌", acronyms: ["哀", "Lam"], korean: "예레미야애가"),
        BibleBook(max: 48, code: "Ezekiel", english: "Ezekiel", chinese: "以西結書", acronyms: ["結", "Ezek", "Eze"], korean: "에스겔"),
        BibleBook(max: 12, code: "Daniel", english: "Daniel", chinese: "但以理書", acronyms: ["但", "Dan"], korean: "다니엘"),
        BibleBook(max: 14, code: "Hosea", english: "Hosea", chinese: "何西阿書", acronyms: ["何", "Hos"], korean: "호세아"),
        BibleBook(max: 3, code: "Joel", english: "Joel", chinese: "約珥書", acronyms: ["珥", "Joel", "Joe"], korean: "요엘"),
        BibleBook(max: 9, code: "Amos", english: "Amos", chinese: "阿摩司書", acronyms: ["摩", "Amos"], korean: "아모스"),
        BibleBook(max: 1, code: "Obadiah", english: "Obadiah", chinese: "俄巴底亞書", acronyms: ["俄", "Obad", "Oba"], korean: "오바댜"),
        BibleBook(max: 4, code: "Jonah", english: "Jonah", chinese: "約拿書", acronyms: ["拿", "Jonah", "Jon"], korean: "요나"),
        BibleBook(max: 7, code: "Micah", english: "Micah", chinese: "彌迦書", acronyms: ["彌", "Mic"], korean: "미가"),
        BibleBook(max: 3, code: "Nahum", english: "Nahum", chinese: "那鴻書", acronyms: ["鴻", "Nah"], korean: "나훔"),
        BibleBook(max: 3, code: "Habakkuk", english: "Habakkuk", chinese: "哈巴谷書", acronyms: ["哈", "Hab"], korean: "하박국"),
        BibleBook(max: 3, code: "Zephaniah", english: "Zephaniah", chinese: "西番雅書", acronyms: ["番", "Zeph", "Zep"], korean: "스바냐"),
        BibleBook(max: 2, code: "Haggai", english: "Haggai", chinese: "哈該書", acronyms: ["該", "Hag"], korean: "학개"),
        BibleBook(max: 14, code: "Zechariah", english: "Zechariah", chinese: "撒迦利亞書", acronyms: ["亞", "Zech", "Zec"], korean: "스가랴"),
        BibleBook(max: 4, code: "Malachi", english: "Malachi", chinese: "瑪拉基書", acronyms: ["瑪", "Mal"], korean: "말라기"),
        BibleBook(max: 28, code: "Matthew", english: "Matthew", chinese: "馬太福音", acronyms: ["太", "Matt", "Mat"], korean: "마태복음"),
        BibleBook(max: 16, code: "Mark", english: "Mark", chinese: "馬可福音", acronyms: ["可", "Mark", "Mak"], korean: "마가복음"),
        BibleBook(max: 24, code: "Luke", english: "Luke", chinese: "路加福音", acronyms: ["路", "Luke", "Luk"], korean: "누가복음"),
        BibleBook(max: 21, code: "John", english: "John", chinese: "約翰福音", acronyms: ["約", "John", "Jhn"], korean: "요한복음"),
        BibleBook(max: 28, code: "Acts", english: "Acts", chinese: "使徒行傳", acronyms: ["徒", "Acts", "Act"], korean: "사도행전"),
        BibleBook(max: 16, code: "Romans", english: "Romans", chinese: "羅馬書", acronyms: ["羅", "Rom"], korean: "로마서"),
        BibleBook(max: 16, code: "1Corinthians", english: "1 Corinthians", chinese: "哥林多前書", acronyms: ["林前", "1Cor", "1Co"], korean: "고린도전서"),
        BibleBook(max: 13, code: "2Corinthians", english: "2 Corinthians", chinese: "哥林多後書", acronyms: ["林後", "2Cor", "2Co"], korean: "고린도후서"),
        BibleBook(max: 6, code: "Galatians", english: "Galatians", chinese: "加拉太書", acronyms: ["加", "Gal"], korean: "갈라디아서"),
        BibleBook(max: 6, code: "Ephesians", english: "Ephesians", chinese: "以弗所書", acronyms: ["弗", "Eph"], korean: "에베소서"),
        BibleBook(max: 4, code: "Philippians", english: "Philippians", chinese: "腓立比書", acronyms: ["腓", "Phil", "Phl"], korean: "빌립보서"),
        BibleBook(max: 4, code: "Colossians", english: "Colossians", chinese: "歌羅西書", acronyms: ["西", "Col"], korean: "골로새서"),
        BibleBook(max: 5, code: "1Thessalonians", english: "1 Thessalonians", chinese: "帖撒羅尼迦前書", acronyms: ["帖前", "1Thess", "1Ts"], korean: "데살로니가전서"),
        BibleBook(max: 3, code: "2Thessalonians", english: "2 Thessalonians", chinese: "帖撒羅尼迦後書", acronyms: ["帖後", "2Thess", "2Ts"], korean: "데살로니가후서"),
        BibleBook(max: 6, code: "1Timothy", english: "1 Timothy", chinese: "提摩太前書", acronyms: ["提前", "1Tim", "1Ti"], korean: "디모데전서"),
        BibleBook(max: 4, code: "2Timothy", english: "2 Timothy", chinese: "提摩太後書", acronyms: ["提後", "2Tim", "2Ti"], korean: "디모데후서"),
        BibleBook(max: 3, code: "Titus", english: "Titus", chinese: "提多書", acronyms: ["多", "Titus", "Tit"], korean: "디도서"),
        BibleBook(max: 1, code: "Philemon", english: "Philemon", chinese: "腓利門書", acronyms: ["門", "Philem", "Phm"], korean: "빌레몬서"),
        BibleBook(max: 13, code: "Hebrews", english: "Hebrews", chinese: "希伯來書", acronyms: ["來", "Heb"], korean: "히브리서"),
        BibleBook(max: 5, code: "James", english: "James", chinese: "雅各書", acronyms: ["雅", "James", "Jas"], korean: "야고보서"),
        BibleBook(max: 5, code: "1Peter", english: "1 Peter", chinese: "彼得前書", acronyms: ["彼前", "1Pet", "1Pe"], korean: "베드로전서"),
        BibleBook(max: 3, code: "2Peter", english: "2 Peter", chinese: "彼得後書", acronyms: ["彼後", "2Pet", "2Pe"], korean: "베드로후서"),
        BibleBook(max: 5, code: "1John", english: "1 John", chinese: "約翰一書", acronyms: ["約一", "1John", "1Jn"], korean: "요한일서"),
        BibleBook(max: 1, code: "2John", english: "2 John", chinese: "約翰二書", acronyms: ["約二", "2John", "2Jn"], korean: "요한이서"),
        BibleBook(max: 1, code: "3John", english: "3 John", chinese: "約翰三書", acronyms: ["約三", "3John", "3Jn"], korean: "요한삼서"),
        BibleBook(max: 1, code: "Jude", english: "Jude", chinese: "猶大書", acronyms: ["猶", "Jude", "Jud"], korean: "유다서"),
        BibleBook(max: 22, code: "Revelation", english: "Revelation", chinese: "啟示錄", acronyms: ["啟", "Rev"], korean: "요한계시록"),
    ]

    // 將書卷＋章轉成從創世記第 1 章起算的 1-based 純章序號（信望愛 read201.cgi 的 chap 參數），
    // 對照原本的 src/domain/interpret.rb
    public static func pureChapterIndex(code: String, chapter: Int) -> Int {
        var i = 0
        for book in books {
            if book.code == code { break }
            i += book.max
        }
        return i + chapter
    }
}

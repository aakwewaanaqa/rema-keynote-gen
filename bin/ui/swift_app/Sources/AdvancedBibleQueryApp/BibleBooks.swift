import Foundation

// 側欄要顯示的中文書名，從 RemaCore 的 Bible.books 取（前 39 卷是舊約）
let oldTestamentBooks = Bible.books.prefix(39).map(\.chinese)
let newTestamentBooks = Bible.books.dropFirst(39).map(\.chinese)

let bookChapterCounts: [String: Int] = Dictionary(
    uniqueKeysWithValues: Bible.books.map { ($0.chinese, $0.max) }
)

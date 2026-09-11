import Foundation

// 主視窗查到的結果存在這裡，另開的檢視視窗透過 environmentObject 拿同一份，
// 用 id 去找對應那一筆，不用把整包 verses 塞進 openWindow(value:) 裡跑序列化
@MainActor
final class BibleSearchResultStore: ObservableObject {
    @Published var results: [BibleSearchResult] = []

    // placeholders 表格放在這裡共用（不是查詢時拍照存進每筆 BibleSearchResult），
    // 這樣不管查詢跟編輯 placeholders 表格的先後順序為何，結果視窗按「產生 Keynote」永遠拿到當下最新的內容——
    // 之前拍照存進 BibleSearchResult 的做法，會導致「查詢完才編輯 placeholders」的操作完全沒生效
    @Published var placeholders: [KeynotePlaceholder] = [
        KeynotePlaceholder(placeholder: "中", format: "{中}")
    ]
}

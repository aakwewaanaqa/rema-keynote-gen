import Foundation

// 主視窗查到的結果存在這裡，另開的檢視視窗透過 environmentObject 拿同一份，
// 用 id 去找對應那一筆，不用把整包 verses 塞進 openWindow(value:) 裡跑序列化
@MainActor
final class BibleSearchResultStore: ObservableObject {
    @Published var results: [BibleSearchResult] = []
}

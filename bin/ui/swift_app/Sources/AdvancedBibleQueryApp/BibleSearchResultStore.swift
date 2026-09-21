import Foundation

// 存到 UserDefaults 裡的那包資料，跟 BibleSearchResultStore 裡要記住的欄位一一對應。
// 版本升級如果要加欄位，讓它們用 optional/預設值解碼，不要動到既有 key，
// 不然使用者升級後舊資料會整包讀不出來、直接被當成沒存過。
private struct PersistedState: Codable {
    var results: [BibleSearchResult]
    var placeholders: [KeynotePlaceholder]
    var searchDsl: String
    var bibleServiceConfig: BibleServiceConfig
}

// 主視窗查到的結果存在這裡，另開的檢視視窗透過 environmentObject 拿同一份，
// 用 id 去找對應那一筆，不用把整包 verses 塞進 openWindow(value:) 裡跑序列化
@MainActor
final class BibleSearchResultStore: ObservableObject {
    private static let defaultsKey = "AdvancedBibleQueryApp.PersistedState"

    // 用來在 init 時把已存檔的內容一次性塞回這幾個 @Published 屬性，
    // 避免載入階段觸發下面的 didSet 又立刻把同一份資料寫回 UserDefaults
    private var isLoading = false

    @Published var results: [BibleSearchResult] = [] {
        didSet { save() }
    }

    // placeholders 表格放在這裡共用（不是查詢時拍照存進每筆 BibleSearchResult），
    // 這樣不管查詢跟編輯 placeholders 表格的先後順序為何，結果視窗按「產生 Keynote」永遠拿到當下最新的內容——
    // 之前拍照存進 BibleSearchResult 的做法，會導致「查詢完才編輯 placeholders」的操作完全沒生效
    @Published var placeholders: [KeynotePlaceholder] = [
        KeynotePlaceholder(placeholder: "中", format: "{中}")
    ] {
        didSet { save() }
    }

    // 搜尋欄位輸入的內容跟譯本勾選狀態放在這裡（而不是 View 的 @State），
    // 才能跟 placeholders/results 用同一套邏輯存檔／還原
    @Published var searchDsl: String = "" {
        didSet { save() }
    }

    @Published var bibleServiceConfig: BibleServiceConfig = .appDefault {
        didSet { save() }
    }

    init() {
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return }

        isLoading = true
        results = state.results
        placeholders = state.placeholders
        searchDsl = state.searchDsl
        bibleServiceConfig = state.bibleServiceConfig
        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        let state = PersistedState(
            results: results,
            placeholders: placeholders,
            searchDsl: searchDsl,
            bibleServiceConfig: bibleServiceConfig
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

import SwiftUI

// 另開視窗顯示單筆查詢結果的經文（不是 popover/sheet，是獨立視窗），
// 透過 AdvancedBibleQueryApp 的第二個 WindowGroup(for: UUID.self) 開啟
struct BibleSearchResultView: View {
    @EnvironmentObject var store: BibleSearchResultStore
    let resultID: UUID?

    var result: BibleSearchResult? {
        guard let resultID else { return nil }
        return store.results.first { $0.id == resultID }
    }

    var body: some View {
        Group {
            if let result {
                List(result.verses, id: \.self) { verse in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(verse.book) \(verse.chapter):\(verse.verse) · \(verse.translation)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(verse.content)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
                .navigationTitle(result.searchDsl)
            } else {
                Text("找不到這筆查詢結果")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .frame(minWidth: 420, minHeight: 400)
    }
}

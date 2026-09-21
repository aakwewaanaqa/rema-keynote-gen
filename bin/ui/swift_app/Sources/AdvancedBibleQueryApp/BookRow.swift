import SwiftUI

// 一列書卷 + 點下去彈出的選章 popover；popover 的開關狀態要各列自己管，所以獨立成一個 View
struct BookRow: View {
    let book: String
    @Binding var searchDsl: String
    @State private var showChapterPicker = false

    var chapterCount: Int { bookChapterCounts[book] ?? 1 }
    let columns = [GridItem(.adaptive(minimum: 36))]

    var body: some View {
        Button(book) { showChapterPicker = true }
            .padding(.vertical, 1)
            .popover(isPresented: $showChapterPicker) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(1...chapterCount, id: \.self) { chapter in
                            Button("\(chapter)") {
                                searchDsl += "\(book)\(chapter)"
                                showChapterPicker = false
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(10)
                }
                .frame(width: 220, height: 260)
            }
    }
}

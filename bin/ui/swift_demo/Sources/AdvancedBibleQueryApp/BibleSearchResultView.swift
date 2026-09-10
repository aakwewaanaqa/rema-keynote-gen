import SwiftUI

// 另開視窗顯示單筆查詢結果的經文（不是 popover/sheet，是獨立視窗），
// 透過 AdvancedBibleQueryApp 的第二個 WindowGroup(for: UUID.self) 開啟
struct BibleSearchResultView: View {
    @EnvironmentObject var store: BibleSearchResultStore
    let resultID: UUID?

    @State private var filterText = ""
    @State private var currentMatchIndex = 0

    var result: BibleSearchResult? {
        guard let resultID else { return nil }
        return store.results.first { $0.id == resultID }
    }

    // 符合搜尋字串的經節在 result.verses 中的索引；只要該節任一譯本符合就算
    var matchedIndices: [Int] {
        guard let result, !filterText.isEmpty else { return [] }
        return result.verses.indices.filter { idx in
            result.verses[idx].translations.contains { translation in
                translation.content.localizedCaseInsensitiveContains(filterText) ||
                translation.book.localizedCaseInsensitiveContains(filterText)
            }
        }
    }

    var body: some View {
        Group {
            if let result {
                ScrollViewReader { proxy in
                    verseList(result: result)
                        .navigationTitle(result.searchDsl)
                        .searchable(text: $filterText, prompt: "在結果中搜尋經節內容")
                        .onSubmit(of: .search) {
                            goToNextMatch(proxy: proxy)
                        }
                        .onChange(of: filterText) { _ in
                            currentMatchIndex = 0
                            scrollToCurrentMatch(proxy: proxy)
                        }
                        .toolbar {
                            searchNavigationToolbar(proxy: proxy)
                        }
                }
            } else {
                Text("找不到這筆查詢結果")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .frame(minWidth: 420, minHeight: 400)
    }

    // 用連續的 VStack 排版（不是 List），視覺上是一整段文字，
    // 沒有 List 自帶的分隔線與選取底色
    private func verseList(result: BibleSearchResult) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(result.verses.enumerated()), id: \.offset) { index, verseGroup in
                    VerseRow(
                        verseGroup: verseGroup,
                        filterText: filterText,
                        isCurrentMatch: currentMatchIndex < matchedIndices.count && matchedIndices[currentMatchIndex] == index
                    )
                    .id(index)
                }
            }
            .padding()
        }
    }

    @ToolbarContentBuilder
    private func searchNavigationToolbar(proxy: ScrollViewProxy) -> some ToolbarContent {
        ToolbarItem {
            Button {
                
            } label: {
                Image(systemName: "hammer")
            }
            .keyboardShortcut("b", modifiers: [.command])
        }
        if !filterText.isEmpty {
            ToolbarItemGroup {
                Text(matchLabel)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .padding(.leading, 10)
                Button {
                    goToPreviousMatch(proxy: proxy)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(matchedIndices.isEmpty)

                Button {
                    goToNextMatch(proxy: proxy)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(matchedIndices.isEmpty)
            }
        }
    }

    private var matchLabel: String {
        guard !matchedIndices.isEmpty else { return "0/0" }
        return "\(currentMatchIndex + 1)/\(matchedIndices.count)"
    }

    private func goToNextMatch(proxy: ScrollViewProxy) {
        guard !matchedIndices.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchedIndices.count
        scrollToCurrentMatch(proxy: proxy)
    }

    private func goToPreviousMatch(proxy: ScrollViewProxy) {
        guard !matchedIndices.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchedIndices.count) % matchedIndices.count
        scrollToCurrentMatch(proxy: proxy)
    }

    private func scrollToCurrentMatch(proxy: ScrollViewProxy) {
        guard matchedIndices.indices.contains(currentMatchIndex) else { return }
        withAnimation {
            proxy.scrollTo(matchedIndices[currentMatchIndex], anchor: .center)
        }
    }
}

// 抽成獨立的 View，避免整個 body 表達式太複雜讓編譯器 type-check 逾時。
// 一節經文一個 row，裡面疊多個譯本（每個譯本各自一小段）
private struct VerseRow: View {
    let verseGroup: QueriedVerseGroup
    let filterText: String
    let isCurrentMatch: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(verseGroup.translations, id: \.self) { translation in
                TranslationRow(
                    verseGroup: verseGroup,
                    translation: translation,
                    filterText: filterText
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .cornerRadius(6)
    }

    private var backgroundColor: Color {
        isCurrentMatch ? Color.accentColor.opacity(0.15) : Color.clear
    }
}

// 同一節經文底下，單一譯本的內容
private struct TranslationRow: View {
    let verseGroup: QueriedVerseGroup
    let translation: VerseTranslation
    let filterText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(translation.book) \(verseGroup.chapter):\(verseGroup.verse) · \(translation.translation)")
                .font(.caption)
                .foregroundColor(.secondary)
            content
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var content: some View {
        if filterText.isEmpty {
            Text(translation.content)
        } else {
            Text(highlightedAttributedString)
        }
    }

    // 把經文內容中符合搜尋字串的片段標黃，其餘保持原樣
    private var highlightedAttributedString: AttributedString {
        var attributed = AttributedString(translation.content)
        guard !filterText.isEmpty else { return attributed }
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: filterText, options: .caseInsensitive) {
            attributed[range].backgroundColor = .yellow
            attributed[range].foregroundColor = .black
            searchStart = range.upperBound
        }
        return attributed
    }
}


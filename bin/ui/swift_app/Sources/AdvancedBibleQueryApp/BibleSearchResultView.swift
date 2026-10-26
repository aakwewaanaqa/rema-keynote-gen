import AppKit
import SwiftUI
import UniformTypeIdentifiers

// 另開視窗顯示單筆查詢結果的經文（不是 popover/sheet，是獨立視窗），
// 透過 AdvancedBibleQueryApp 的第二個 WindowGroup(for: UUID.self) 開啟
struct BibleSearchResultView: View {
    @EnvironmentObject var store: BibleSearchResultStore
    let resultID: UUID?

    @State private var filterText = ""
    @State private var currentMatchIndex = 0

    @State private var isGeneratingKeynote = false
    @State private var generateSuccessMessage = ""
    @State private var isGenerateSuccessDisplaying = false
    @State private var generateErrorDetail: String?
    @State private var isGenerateErrorDisplaying = false

    // #filePath 在 Sources/AdvancedBibleQueryApp/BibleSearchResultView.swift，
    // 往上三層回到 swift_app 目錄，對照 advanced_bible_query_cli.rb / generate_keynote_cli.rb 所在位置
    private let scriptDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    // scriptDir(swift_app) 再往上兩層是專案根目錄，keynotes/ 底下放現成的範本檔，
    // 挑範本檔的面板預設從這裡開，使用者少翻幾層資料夾
    private var defaultTemplateDir: URL {
        scriptDir.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("keynotes")
    }

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

    // 分享／複製整段查詢結果用的純文字，排版跟畫面上一節一節疊著看到的一樣
    // （書卷 章:節 · 譯本 + 內容），不是丟一包 JSON 給別人看
    private var shareText: String {
        guard let result else { return "" }
        return result.verses.map { verseGroup in
            verseGroup.translations.map { translation in
                "\(translation.book) \(verseGroup.chapter):\(verseGroup.verse) · \(translation.translation)\n\(translation.content)"
            }.joined(separator: "\n\n")
        }.joined(separator: "\n\n")
    }

    // 把 shareText 寫成暫存檔給分享用（見 SharingPickerButtonView 的說明：AirDrop 對純文字
    // 支援不穩定，分享檔案才穩定會出現 AirDrop）。用查詢字串當檔名，方便對方收到後看得懂內容
    private func writeShareFile() -> URL? {
        guard let result, !shareText.isEmpty else { return nil }
        let safeName = result.searchDsl
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = (safeName.isEmpty ? "經文" : safeName) + ".txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try shareText.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
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
        .sheet(isPresented: $isGenerateErrorDisplaying) {
            ErrorDetailView(detail: generateErrorDetail ?? "", isPresented: $isGenerateErrorDisplaying)
        }
        .sheet(isPresented: $isGenerateSuccessDisplaying) {
            ErrorDetailView(
                title: "Keynote 已產生",
                detail: generateSuccessMessage,
                isPresented: $isGenerateSuccessDisplaying
            )
        }
    }

    // 依序跳範本選擇、母片選單、輸出資料夾面板，都選好才真的動 Keynote（osascript 開檔/加投影片/匯出/關檔），
    // 使用者取消任一步就整個放棄，不做部分執行。開著的檔案清單、母片清單都要透過 osascript 問 Keynote
    // （母片那步約要等幾秒），所以一開始就把 isGeneratingKeynote 設起來，讓工具列按鈕轉圈、也擋住重複點擊
    private func generateKeynote(for result: BibleSearchResult) {
        guard !isGeneratingKeynote else { return }

        isGeneratingKeynote = true
        Task.detached {
            // 問不到開著的檔案（例如沒給 Keynote 自動化權限）不算錯，直接退回只用檔案面板挑範本
            let openDocuments = (try? runListKeynoteOpenDocumentsCLI().get()) ?? []
            await MainActor.run {
                guard let templateURL = pickTemplate(openDocuments: openDocuments) else {
                    isGeneratingKeynote = false
                    return
                }
                chooseMasterAndGenerate(for: result, templateURL: templateURL)
            }
        }
    }

    private func chooseMasterAndGenerate(for result: BibleSearchResult, templateURL: URL) {
        Task.detached {
            let layoutsOutcome = runListKeynoteLayoutsCLI(templatePath: templateURL.path)
            await MainActor.run {
                switch layoutsOutcome {
                case .success(let layouts):
                    guard let masterChoice = pickMasterSlide(layouts: layouts),
                          let outputDirURL = pickOutputDirectory()
                    else {
                        isGeneratingKeynote = false
                        return
                    }
                    runGenerateKeynote(
                        for: result,
                        templateURL: templateURL,
                        outputDirURL: outputDirURL,
                        masterName: masterChoice.name
                    )
                case .failure(let error):
                    isGeneratingKeynote = false
                    showGenerateError(error)
                }
            }
        }
    }

    private func runGenerateKeynote(
        for result: BibleSearchResult,
        templateURL: URL,
        outputDirURL: URL,
        masterName: String?
    ) {
        let rawText = result.searchDsl
        let enabledTokens = result.config.enabledTokens
        let resultPlaceholders = store.placeholders

        Task.detached {
            let outcome = runGenerateKeynoteCLI(
                rawText: rawText,
                enabledTokens: enabledTokens,
                templatePath: templateURL.path,
                outputDir: outputDirURL.path,
                placeholders: resultPlaceholders,
                masterName: masterName
            )
            await MainActor.run {
                isGeneratingKeynote = false
                switch outcome {
                case .success(let (status, exportDir, keynotePath, warnings)):
                    var lines = [status]
                    if let exportDir { lines.append("輸出位置：\(exportDir)") }
                    if let keynotePath { lines.append("簡報已存成並保持開啟：\(keynotePath)") }
                    lines.append(contentsOf: warnings)
                    generateSuccessMessage = lines.joined(separator: "\n")
                    isGenerateSuccessDisplaying = true
                case .failure(let error):
                    showGenerateError(error)
                }
            }
        }
    }

    private func showGenerateError(_ error: GenerateKeynoteError) {
        let detail = [error.message, error.detail].compactMap { $0 }.filter { !$0.isEmpty }
        generateErrorDetail = detail.joined(separator: "\n\n---\n\n")
        isGenerateErrorDisplaying = true
    }

    // 選單第一項是「沿用第 1 張投影片的母片」（name 為 nil，也就是原本的行為），其後列出範本裡所有母片。
    // 回傳 nil 代表使用者按了取消；用一層 struct 包起來，才分得出「取消」跟「選了預設」
    private struct MasterSlideChoice {
        let name: String?
    }

    private func pickMasterSlide(layouts: [String]) -> MasterSlideChoice? {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        popup.addItem(withTitle: "沿用第 1 張投影片的母片")
        if !layouts.isEmpty {
            popup.menu?.addItem(.separator())
            // 用 NSMenuItem 直接加，不用 addItems(withTitles:)：後者遇到同名項目會把前一個蓋掉
            for layout in layouts {
                popup.menu?.addItem(NSMenuItem(title: layout, action: nil, keyEquivalent: ""))
            }
        }

        let alert = NSAlert()
        alert.messageText = "選擇母片"
        alert.informativeText = "新投影片會套用這張母片，母片裡的文字框內容要跟 placeholder 對得上才會被替換。"
        alert.accessoryView = popup
        alert.addButton(withTitle: "下一步")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        return MasterSlideChoice(name: popup.indexOfSelectedItem == 0 ? nil : popup.titleOfSelectedItem)
    }

    // Keynote 有開著（且存過檔）的文件就先跳選單讓使用者直接挑，最後一項「選擇其他檔案…」才開檔案面板；
    // 沒有開著的文件就直接開檔案面板，跟原本一樣。產生時用的是範本的暫存複本（見 KeynoteRunner.with_template_copy），
    // 開著的那份文件不會被動到，但也代表沒存檔的變更不會反映出來，所以有未儲存變更的項目要標出來
    private func pickTemplate(openDocuments: [KeynoteOpenDocument]) -> URL? {
        guard !openDocuments.isEmpty else { return pickTemplateFile() }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        // 用 NSMenuItem 直接加，不用 addItems(withTitles:)：後者遇到同名項目（不同資料夾的同名檔）會把前一個蓋掉
        for document in openDocuments {
            let url = URL(fileURLWithPath: document.path)
            let title = url.lastPathComponent + (document.modified ? "（有未儲存的變更）" : "")
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.toolTip = document.path
            popup.menu?.addItem(item)
        }
        popup.menu?.addItem(.separator())
        popup.menu?.addItem(NSMenuItem(title: "選擇其他檔案…", action: nil, keyEquivalent: ""))

        let alert = NSAlert()
        alert.messageText = "選擇 Keynote 範本"
        alert.informativeText = "可以直接使用 Keynote 中開著的檔案。產生時會用檔案上次儲存的內容，不會更動開著的文件；有未儲存的變更請先存檔。"
        alert.accessoryView = popup
        alert.addButton(withTitle: "下一步")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let index = popup.indexOfSelectedItem
        guard openDocuments.indices.contains(index) else { return pickTemplateFile() }
        return URL(fileURLWithPath: openDocuments[index].path)
    }

    private func pickTemplateFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "選擇 Keynote 範本"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "key")].compactMap { $0 }
        if FileManager.default.fileExists(atPath: defaultTemplateDir.path) {
            panel.directoryURL = defaultTemplateDir
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func pickOutputDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "選擇投影片輸出資料夾"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
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
                if let result { generateKeynote(for: result) }
            } label: {
                if isGeneratingKeynote {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "hammer")
                }
            }
            .keyboardShortcut("b", modifiers: [.command])
            .disabled(result == nil || isGeneratingKeynote)
            .help("產生 Keynote")
        }
        ToolbarItem {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(shareText, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(result == nil)
            .help("複製全部經文")
        }
        ToolbarItem {
            SharingPickerToolbarButton(
                itemsProvider: { writeShareFile().map { [$0] } ?? [] },
                isEnabled: result != nil
            )
            .help("分享（AirDrop、訊息…）")
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

// 實測發現：分享「純文字字串」時 AirDrop 常常不會出現在清單裡（不管是 ShareLink 還是
// NSSharingServicePicker 都一樣），但分享「檔案」AirDrop 就一定在——這是 AirDrop 本身
// 對文字型別支援不穩定，不是這兩個 API 的問題。所以改成點下分享才把經文寫成暫存 .txt 檔，
// 拿檔案去觸發分享，跟 Finder 分享檔案走同一條路。itemsProvider 用閉包延後到點擊當下才算，
// 避免每次畫面重繪都在寫暫存檔。
private final class SharingPickerButtonView: NSButton {
    var itemsProvider: () -> [Any] = { [] }

    convenience init() {
        self.init(frame: .zero)
        bezelStyle = .texturedRounded
        isBordered = false
        image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "分享")
        imagePosition = .imageOnly
        target = self
        action = #selector(showPicker)
    }

    @objc private func showPicker() {
        let items = itemsProvider()
        guard !items.isEmpty else { return }
        NSSharingServicePicker(items: items).show(relativeTo: bounds, of: self, preferredEdge: .minY)
    }
}

private struct SharingPickerToolbarButton: NSViewRepresentable {
    let itemsProvider: () -> [Any]
    let isEnabled: Bool

    func makeNSView(context: Context) -> SharingPickerButtonView {
        let view = SharingPickerButtonView()
        view.itemsProvider = itemsProvider
        view.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: SharingPickerButtonView, context: Context) {
        nsView.itemsProvider = itemsProvider
        nsView.isEnabled = isEnabled
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


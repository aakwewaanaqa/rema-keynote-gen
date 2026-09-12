import SwiftUI
import AppKit

struct BibleServiceConfig: Identifiable, Hashable {
    var id = UUID()
    var fhl: Bool
    var biblegatewayNiv: Bool
    var biblegatewayNkjv: Bool
    var biblegatewayKjv: Bool
    var holynetGaeYeogGaeJeong: Bool

    public static var appDefault: BibleServiceConfig {
        BibleServiceConfig(
            fhl: true,
            biblegatewayNiv: true,
            biblegatewayNkjv: false,
            biblegatewayKjv: false,
            holynetGaeYeogGaeJeong: false
        )
    }

    // hare 選單要塞哪些語言的 token，直接對照目前勾選的來源，每個語言互不影響。
    var selectedLanguages: [TranslationLanguage] {
        var languages: [TranslationLanguage] = []
        if fhl { languages.append(.cuv) }
        if biblegatewayNiv { languages.append(.niv) }
        if biblegatewayNkjv { languages.append(.nkjv) }
        if biblegatewayKjv { languages.append(.kjv) }
        if holynetGaeYeogGaeJeong { languages.append(.gae) }
        return languages
    }

    // 傳給 CLI 的啟用來源 token，對照 advanced_bible_query_cli.rb / generate_keynote_cli.rb 的 token_sources
    var enabledTokens: String {
        var tokens: [String] = []
        if fhl { tokens.append("fhl") }
        if biblegatewayNiv { tokens.append("niv") }
        if biblegatewayNkjv { tokens.append("nkjv") }
        if biblegatewayKjv { tokens.append("kjv") }
        if holynetGaeYeogGaeJeong { tokens.append("gae") }
        return tokens.joined(separator: ",")
    }
}

struct BibleSearchResult: Identifiable {
    var id = UUID()
    var searchDsl: String
    var config: BibleServiceConfig
    var verses: [QueriedVerseGroup]
}

struct AdvancedBibleQueryView: View {
    @EnvironmentObject var resultStore: BibleSearchResultStore
    @Environment(\.openWindow) private var openWindow

    @State var searchDsl                     = ""
    @State var isSearchConfirmDisplaying     = false
    @State var bibleServiceConfig            = BibleServiceConfig.appDefault
    @State var isCommonFormatPopupDisplaying = false

    @State var status    = ""
    @State var isRunning = false

    // 查詢失敗時把完整錯誤訊息（含 CLI 的 stderr 診斷內容）存起來，用彈窗顯示方便複製，
    // 不然逾時這種情況光看 status 那行文字根本看不出卡在哪一步
    @State var errorDetail: String?
    @State var isErrorDetailDisplaying = false

    // 查詢「成功」但個別來源掛掉（例如某聖經網站故障）的警告，跟上面的失敗彈窗共用
    // ErrorDetailView，只是換個標題——這種訊息使用者常常要整段複製貼給我回報狀況，
    // 塞進 status 那行 caption 太短會被截斷，且不能選取文字
    @State var sourceErrorDetail: String?
    @State var isSourceErrorDetailDisplaying = false

    // #filePath 是 Sources/AdvancedBibleQueryApp/AdvancedBibleQueryView.swift，
    // 要往上三層（檔名 -> target 目錄 -> Sources 目錄）才會回到 advanced_bible_query_cli.rb 所在的 swift_demo 目錄
    private let scriptDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    // 查詢負責把經文貼進預覽；#region/{token} 範本代換留到「產生 Keynote」那一步再處理，
    // placeholders 表格不跟著查詢結果走，放在 resultStore 共用（見 BibleSearchResultStore）
    func runQuery() {
        guard !isRunning else { return }
        isRunning = true
        status = "查詢中..."
        let rawText = searchDsl
        let enabledTokens = bibleServiceConfig.enabledTokens
        let config = bibleServiceConfig

        Task.detached { [scriptDir] in
            let result = runBibleQueryCLI(scriptDir: scriptDir, rawText: rawText, enabledTokens: enabledTokens)
            await MainActor.run {
                self.isRunning = false
                switch result {
                case .success(let (status, verses, sourceErrors)):
                    self.status = status
                    self.resultStore.results.append(
                        BibleSearchResult(searchDsl: rawText, config: config, verses: verses))
                    if !sourceErrors.isEmpty {
                        self.sourceErrorDetail = sourceErrors.joined(separator: "\n\n---\n\n")
                        self.isSourceErrorDetailDisplaying = true
                    }
                case .failure(let error):
                    self.status = "查詢失敗: \(error.message)"
                    let detail = [error.message, error.detail].compactMap { $0 }.filter { !$0.isEmpty }
                    self.errorDetail = detail.joined(separator: "\n\n---\n\n")
                    self.isErrorDetailDisplaying = true
                }
            }
        }
    }

    func binding<Item: Identifiable, Value>(
        _ items: Binding<[Item]>,
        id: Item.ID,
        _ keypath: WritableKeyPath<Item, Value>
    ) -> Binding<Value> {
        Binding(
            get: { items.wrappedValue.first { $0.id == id }![keyPath: keypath] },
            set: { newVal in
                guard let idx = items.wrappedValue.firstIndex(where: { $0.id == id }) else { return }
                items.wrappedValue[idx][keyPath: keypath] = newVal
            })
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section("舊約") {
                    ForEach(oldTestamentBooks, id: \.self) { book in
                        BookRow(book: book, searchDsl: $searchDsl)
                    }
                }
                Section("新約") {
                    ForEach(newTestamentBooks, id: \.self) { book in
                        BookRow(book: book, searchDsl: $searchDsl)
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 20)
        } content: {
            VStack(alignment: .leading) {
                Toggle(isOn: $bibleServiceConfig.fhl) {
                    Text("信望愛 CUV")
                }
                Toggle(isOn: $bibleServiceConfig.biblegatewayNiv) {
                    Text("NIV")
                }
                Toggle(isOn: $bibleServiceConfig.biblegatewayNkjv) {
                    Text("NKJV")
                }
                Toggle(isOn: $bibleServiceConfig.biblegatewayKjv) {
                    Text("KJV")
                }
                Toggle(isOn: $bibleServiceConfig.holynetGaeYeogGaeJeong) {
                    Text("개역개겅")
                }

                Divider()

                ProgressView(value: isRunning ? nil : 0)
                    .opacity(isRunning ? 1 : 0)

                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                List(resultStore.results) { result in
                    Button {
                        openWindow(value: result.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.searchDsl)
                                .font(.headline)
                            Text("\(result.verses.count) 節")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 200)
            }
            .padding()
        } detail: {
            Table(resultStore.placeholders) {
                TableColumn("") { item in
                    HStack(alignment: .center, spacing: 16) {
                        Button {
                            guard resultStore.placeholders.count > 1 else { return }
                            resultStore.placeholders.removeAll(where: { $0.id == item.id })
                        } label: {
                            Image(systemName: "trash")
                        }.foregroundColor(.red).buttonStyle(.borderless)

                        Button {
                            let newItem = KeynotePlaceholder(
                                placeholder: "String", format: "String")
                            guard let idx = resultStore.placeholders.firstIndex(where: { $0.id == item.id })
                            else {
                                resultStore.placeholders.append(newItem)
                                return
                            }
                            resultStore.placeholders.insert(newItem, at: idx + 1)
                        } label: {
                            Image(systemName: "plus")
                        }.foregroundColor(.green).buttonStyle(.borderless)
                    }
                }.width(60)

                TableColumn("佔位符") { item in
                    TextField("佔位符", text: binding($resultStore.placeholders, id: item.id, \.placeholder))
                        .textFieldStyle(.roundedBorder)
                }

                TableColumn("格式") { item in
                    TextField("格式", text: binding($resultStore.placeholders, id: item.id, \.format))
                        .textFieldStyle(.roundedBorder)
                }
            }
            Divider()
            VStack(alignment: .leading) {
                Button {
                    isCommonFormatPopupDisplaying = true
                } label: {
                    Image(systemName: "hare")
                }.popover(isPresented: $isCommonFormatPopupDisplaying) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("動畫").font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))]) {
                            Button {
                                resultStore.placeholders = KeynotePlaceholder.preset(
                                    languages: bibleServiceConfig.selectedLanguages,
                                    layout: .allMerged
                                )
                            } label: {
                                Text("全合")
                            }
                        }
                        Divider()
                        Text("字幕").font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))]) {
                            Button {
                                resultStore.placeholders = KeynotePlaceholder.preset(
                                    languages: bibleServiceConfig.selectedLanguages,
                                    layout: .bookMergedRangeSeparate
                                )
                            } label: {
                                Text("書合")
                            }
                            Button {
                                resultStore.placeholders = KeynotePlaceholder.preset(
                                    languages: bibleServiceConfig.selectedLanguages,
                                    layout: .bookSplitRangeSeparate
                                )
                            } label: {
                                Text("書分")
                            }
                        }
                    }.padding(.all, 16).frame(width: 250)
                }
            }.padding(.all, 8)
        }
        .searchable(text: $searchDsl, prompt: "找聖經")
        .onSubmit(of: .search) {
            isSearchConfirmDisplaying = true
        }
        .alert("要查詢經文嗎？", isPresented: $isSearchConfirmDisplaying) {
            Button("查詢") { runQuery() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(searchDsl)
        }
        .sheet(isPresented: $isErrorDetailDisplaying) {
            ErrorDetailView(detail: errorDetail ?? "", isPresented: $isErrorDetailDisplaying)
        }
        .sheet(isPresented: $isSourceErrorDetailDisplaying) {
            ErrorDetailView(
                title: "查詢完成，但有來源出狀況",
                detail: sourceErrorDetail ?? "",
                isPresented: $isSourceErrorDetailDisplaying
            )
        }
    }
}

// 原生 .alert 在 macOS 上文字沒辦法選取複製，逾時、來源網站故障這種要貼給別人看的訊息，
// 用可以整段選取/複製的 sheet 取代單純顯示用的 alert。title 可以套失敗也可以套「成功但有警告」，
// 不是 private：BibleSearchResultView 的「產生 Keynote」錯誤/警告也共用這個元件
struct ErrorDetailView: View {
    var title: String = "查詢失敗"
    var detail: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ScrollView {
                Text(detail)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 480, minHeight: 240)
            HStack {
                Spacer()
                Button("複製") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(detail, forType: .string)
                }
                Button("關閉") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}

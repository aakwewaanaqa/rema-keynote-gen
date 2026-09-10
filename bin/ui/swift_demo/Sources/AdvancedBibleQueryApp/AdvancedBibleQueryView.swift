import SwiftUI

struct BibleServiceConfig: Identifiable, Hashable {
    var id = UUID()
    var fhl: Bool
    var biblegatewayNiv: Bool
    var biblegatewayNkjv: Bool
    var holynetGaeYeogGaeJeong: Bool
    
    public static var appDefault: BibleServiceConfig {
        BibleServiceConfig(
            fhl: true,
            biblegatewayNiv: true,
            biblegatewayNkjv: false,
            holynetGaeYeogGaeJeong: false
        )
    }
}

struct BibleSearchResult: Identifiable {
    var id = UUID()
    var searchDsl: String
    var config: BibleServiceConfig
    var verses: [QueriedVerse]
}

struct AdvancedBibleQueryView: View {
    @EnvironmentObject var resultStore: BibleSearchResultStore
    @Environment(\.openWindow) private var openWindow

    @State var searchDsl                 = ""
    @State var isSearchConfirmDisplaying = false
    @State var bibleServiceConfig        = BibleServiceConfig.appDefault

    @State var placeholders: [KeynotePlaceholder] = [
        KeynotePlaceholder(placeholder: "中", format: "{中}")
    ]

    @State var status    = ""
    @State var isRunning = false

    // #filePath 是 Sources/AdvancedBibleQueryApp/AdvancedBibleQueryView.swift，
    // 要往上三層（檔名 -> target 目錄 -> Sources 目錄）才會回到 advanced_bible_query_cli.rb 所在的 swift_demo 目錄
    private let scriptDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    // 勾選框決定要傳給 CLI 哪些啟用的來源 token，對照 advanced_bible_query_cli.rb 的 token_sources
    func enabledSourceTokens() -> String {
        var tokens: [String] = []
        if bibleServiceConfig.fhl { tokens.append("fhl") }
        if bibleServiceConfig.biblegatewayNiv { tokens.append("niv") }
        if bibleServiceConfig.biblegatewayNkjv { tokens.append("nkjv") }
        if bibleServiceConfig.holynetGaeYeogGaeJeong { tokens.append("gae") }
        return tokens.joined(separator: ",")
    }

    // 查詢只負責把經文貼進預覽；#region/{token} 範本代換留到「產生 Keynote」那一步再處理，
    // 所以這裡不會用到 placeholders 表格的內容
    func runQuery() {
        guard !isRunning else { return }
        isRunning = true
        status = "查詢中..."
        let rawText = searchDsl
        let enabledTokens = enabledSourceTokens()
        let config = bibleServiceConfig

        Task.detached { [scriptDir] in
            let result = runBibleQueryCLI(scriptDir: scriptDir, rawText: rawText, enabledTokens: enabledTokens)
            await MainActor.run {
                self.isRunning = false
                switch result {
                case .success(let (status, verses)):
                    self.status = status
                    self.resultStore.results.append(
                        BibleSearchResult(searchDsl: rawText, config: config, verses: verses))
                case .failure(let error):
                    self.status = "查詢失敗: \(error.message)"
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
                Toggle(isOn: $bibleServiceConfig.holynetGaeYeogGaeJeong) {
                    Text("개역개겅")
                }

                Divider()
                    .padding(.vertical, 4)

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
            Table(placeholders) {
                TableColumn("") { item in
                    HStack {
                        Button {
                            guard placeholders.count > 1 else { return }
                            placeholders.removeAll(where: { $0.id == item.id })
                        } label: {
                            Image(systemName: "trash")
                        }
                        .foregroundColor(.red)
                        .buttonStyle(.bordered)

                        Button {
                            let newItem = KeynotePlaceholder(
                                placeholder: "String", format: "String")
                            guard let idx = placeholders.firstIndex(where: { $0.id == item.id })
                            else {
                                placeholders.append(newItem)
                                return
                            }
                            placeholders.insert(newItem, at: idx + 1)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .foregroundColor(.green)
                        .buttonStyle(.bordered)
                    }
                }.width(60)

                TableColumn("佔位符") { item in
                    TextField("佔位符", text: binding($placeholders, id: item.id, \.placeholder))
                        .textFieldStyle(.roundedBorder)
                }

                TableColumn("格式") { item in
                    TextField("格式", text: binding($placeholders, id: item.id, \.format))
                        .textFieldStyle(.roundedBorder)
                }
            }
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
    }
}

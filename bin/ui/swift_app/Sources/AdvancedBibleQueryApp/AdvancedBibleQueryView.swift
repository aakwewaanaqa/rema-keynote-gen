import AppKit
import Combine
import SwiftUI

struct BibleServiceConfig: Identifiable, Hashable, Codable {
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

    // 查詢紀錄列表要顯示這筆查了哪些譯本，文字對照上面 Toggle 的 label
    var displayNames: [String] {
        var names: [String] = []
        if fhl { names.append("信望愛 CUV") }
        if biblegatewayNiv { names.append("NIV") }
        if biblegatewayNkjv { names.append("NKJV") }
        if biblegatewayKjv { names.append("KJV") }
        if holynetGaeYeogGaeJeong { names.append("개역개겅") }
        return names
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

struct BibleSearchResult: Identifiable, Codable {
    var id = UUID()
    var searchDsl: String
    var config: BibleServiceConfig
    var verses: [QueriedVerseGroup]
}

struct AdvancedBibleQueryView: View {
    @EnvironmentObject var resultStore: BibleSearchResultStore
    @Environment(\.openWindow) private var openWindow

    @State var isSearchConfirmDisplaying = false
    @State var isCommonFormatPopupDisplaying = false

    @State var status = ""
    @State var isRunning = false

    // 查詢中彈窗：擋住整個視窗讓使用者不用管它，裡面有不確定進度圈跟取消按鈕。
    // currentQueryTask 留著是為了讓「取消」按鈕能叫到底層還在跑的 ruby process
    @State var isProgressSheetDisplaying = false
    @State var queryStartedAt: Date?
    @State var currentQueryTask: BibleQueryTask?

    // 查詢失敗時把完整錯誤訊息（含 CLI 的 stderr 診斷內容）存起來，用彈窗顯示方便複製，
    // 不然逾時這種情況光看 status 那行文字根本看不出卡在哪一步
    @State var errorDetail: String?
    @State var isErrorDetailDisplaying = false

    // 查詢「成功」但個別來源掛掉（例如某聖經網站故障）的警告，跟上面的失敗彈窗共用
    // ErrorDetailView，只是換個標題——這種訊息使用者常常要整段複製貼給我回報狀況，
    // 塞進 status 那行 caption 太短會被截斷，且不能選取文字
    @State var sourceErrorDetail: String?
    @State var isSourceErrorDetailDisplaying = false

    // 查詢負責把經文貼進預覽；#region/{token} 範本代換留到「產生 Keynote」那一步再處理，
    // placeholders 表格不跟著查詢結果走，放在 resultStore 共用（見 BibleSearchResultStore）
    func runQuery() {
        guard !isRunning else { return }
        isRunning = true
        isProgressSheetDisplaying = true
        queryStartedAt = Date()
        status = "查詢中..."
        let rawText = resultStore.searchDsl
        let enabledTokens = resultStore.bibleServiceConfig.enabledTokens
        let config = resultStore.bibleServiceConfig

        let task = BibleQueryTask()
        currentQueryTask = task
        task.start(rawText: rawText, enabledTokens: enabledTokens) { result in
            self.isRunning = false
            self.isProgressSheetDisplaying = false
            self.currentQueryTask = nil
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
                // 使用者主動取消不算查詢失敗，不用彈錯誤詳情視窗
                if error is QueryCancelledError {
                    self.status = "已取消查詢"
                    return
                }
                guard let queryError = error as? QueryError else { return }
                self.status = "查詢失敗: \(queryError.message)"
                let detail = [queryError.message, queryError.detail].compactMap { $0 }.filter {
                    !$0.isEmpty
                }
                self.errorDetail = detail.joined(separator: "\n\n---\n\n")
                self.isErrorDetailDisplaying = true
            }
        }
    }

    func cancelQuery() {
        currentQueryTask?.cancel()
    }

    func binding<Item: Identifiable, Value>(
        _ items: Binding<[Item]>,
        id: Item.ID,
        _ keypath: WritableKeyPath<Item, Value>
    ) -> Binding<Value> {
        Binding(
            get: { items.wrappedValue.first { $0.id == id }![keyPath: keypath] },
            set: { newVal in
                guard let idx = items.wrappedValue.firstIndex(where: { $0.id == id }) else {
                    return
                }
                items.wrappedValue[idx][keyPath: keypath] = newVal
            })
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section("舊約") {
                    ForEach(oldTestamentBooks, id: \.self) { book in
                        BookRow(book: book, searchDsl: $resultStore.searchDsl)
                    }
                }
                Section("新約") {
                    ForEach(newTestamentBooks, id: \.self) { book in
                        BookRow(book: book, searchDsl: $resultStore.searchDsl)
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 20)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 4) {
                    Toggle(isOn: $resultStore.bibleServiceConfig.fhl) {
                        Text("信望愛 CUV").font(.caption)
                    }.toggleStyle(.button)
                    Toggle(isOn: $resultStore.bibleServiceConfig.biblegatewayNiv) {
                        Text("NIV").font(.caption)
                    }.toggleStyle(.button)
                    Toggle(isOn: $resultStore.bibleServiceConfig.biblegatewayNkjv) {
                        Text("NKJV").font(.caption)
                    }.toggleStyle(.button)
                    Toggle(isOn: $resultStore.bibleServiceConfig.biblegatewayKjv) {
                        Text("KJV").font(.caption)
                    }.toggleStyle(.button)
                    Toggle(isOn: $resultStore.bibleServiceConfig.holynetGaeYeogGaeJeong) {
                        Text("개역개겅").font(.caption)
                    }.toggleStyle(.button)
                }.padding(.vertical, 8).padding(.horizontal, 12)

                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Table(resultStore.results) {
                    TableColumn("") { result in
                        Button {
                            resultStore.results.removeAll { $0.id == result.id }
                        } label: {
                            Image(systemName: "trash")
                        }.foregroundColor(.red).buttonStyle(.borderless)
                    }.width(30)

                    TableColumn("查詢") { result in
                        if #available(macOS 26.0, *) {
                            Button {
                                openWindow(value: result.id)
                            } label: {
                                Text(result.searchDsl)
                            }.buttonStyle(.glassProminent)
                        } else {
                            Button {
                                openWindow(value: result.id)
                            } label: {
                                Text(result.searchDsl)
                            }.buttonStyle(.borderedProminent)
                        }
                    }

                    TableColumn("譯本") { result in
                        Text(result.config.displayNames.joined(separator: "、"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    TableColumn("節數") { result in
                        Text("\(result.verses.count)")
                    }.width(50)
                }
                .frame(minHeight: 200)
            }
        } detail: {
            VStack(alignment: .leading) {
                Button {
                    isCommonFormatPopupDisplaying = true
                } label: {
                    Image(systemName: "hare")
                }
                .popover(isPresented: $isCommonFormatPopupDisplaying) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("動畫").font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))]) {
                            Button {
                                resultStore.placeholders = KeynotePlaceholder.preset(
                                    languages: resultStore.bibleServiceConfig.selectedLanguages,
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
                                    languages: resultStore.bibleServiceConfig.selectedLanguages,
                                    layout: .bookMergedRangeSeparate
                                )
                            } label: {
                                Text("書合")
                            }
                            Button {
                                resultStore.placeholders = KeynotePlaceholder.preset(
                                    languages: resultStore.bibleServiceConfig.selectedLanguages,
                                    layout: .bookSplitRangeSeparate
                                )
                            } label: {
                                Text("書分")
                            }
                        }
                    }.padding(.all, 16).frame(width: 250)
                }
            }.padding(.all, 8)
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
                            guard
                                let idx = resultStore.placeholders.firstIndex(where: {
                                    $0.id == item.id
                                })
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
                    TextField(
                        "佔位符", text: binding($resultStore.placeholders, id: item.id, \.placeholder)
                    )
                    .textFieldStyle(.roundedBorder)
                }

                TableColumn("格式") { item in
                    TextField("格式", text: binding($resultStore.placeholders, id: item.id, \.format))
                        .textFieldStyle(.roundedBorder)
                }
            }

        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: "lyrics-composer")
                } label: {
                    Label("歌詞整理", systemImage: "music.note.list")
                }
            }
        }
        .searchable(text: $resultStore.searchDsl, prompt: "找聖經")
        .onSubmit(of: .search) {
            isSearchConfirmDisplaying = true
        }
        .alert("要查詢經文嗎？", isPresented: $isSearchConfirmDisplaying) {
            Button("查詢") { runQuery() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(resultStore.searchDsl)
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
        // 查詢中彈窗：擋住整個視窗（macOS 的 sheet 不會被點外面或滑動手勢關掉），
        // 使用者只能按裡面的「取消」，不用擔心誤觸別的地方
        .sheet(isPresented: $isProgressSheetDisplaying) {
            QueryProgressSheet(startedAt: queryStartedAt ?? Date(), onCancel: cancelQuery)
                .interactiveDismissDisabled()
        }
    }
}

// 查詢中顯示的彈窗：不確定進度圈 + 已耗時秒數 + 現在這台 Mac 的網路上下傳速度 + 取消按鈕。
// 網路速度是量整台機器的網路介面流量（跟 Activity Monitor 同一種數字），不是這次查詢本身傳了多少資料——
// 帶查經班的人在教會現場常常 Wi-Fi 很多人擠，這裡是要讓人一眼看出「現在是不是網路本身就很慢」。
// 取消會真的把底層 ruby process 終止掉，見 BibleQueryTask.cancel()
private struct QueryProgressSheet: View {
    let startedAt: Date
    let onCancel: () -> Void

    @State private var elapsed: TimeInterval = 0
    @StateObject private var networkMonitor = NetworkThroughputMonitor()
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("查詢中…")
                .font(.headline)
            Text(String(format: "已耗時 %.1f 秒", elapsed))
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()

            HStack(spacing: 16) {
                Label(formatSpeed(networkMonitor.downloadKBps), systemImage: "arrow.down")
                Label(formatSpeed(networkMonitor.uploadKBps), systemImage: "arrow.up")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .monospacedDigit()

            Button("取消", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 260)
        .onReceive(timer) { now in
            elapsed = now.timeIntervalSince(startedAt)
        }
        .onAppear { networkMonitor.start() }
        .onDisappear { networkMonitor.stop() }
    }

    private func formatSpeed(_ kbps: Double) -> String {
        kbps >= 1024
            ? String(format: "%.1f MB/s", kbps / 1024)
            : String(format: "%.0f KB/s", kbps)
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

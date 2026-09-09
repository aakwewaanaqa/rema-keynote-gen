// SwiftUI 版的進階查詢視窗，對照 bin/ui/windows/advanced_bible_query_window.rb（Glimmer LibUI 版）。
// 查詢/範本邏輯不重寫，沿用 swift_demo 目錄下的 advanced_bible_query_cli.rb（透過 Process 呼叫 Ruby，JSON 交換資料），
// 這支只負責 UI 跟事件處理。
// 執行方式：cd bin/ui/swift_demo && swift run AdvancedBibleQueryApp

import AppKit
import Foundation
import SwiftUI

struct QueryResult: Decodable {
    let status: String?
    let preview: String?
    let error: String?
}

struct QueryError: Error {
    let message: String
}

@MainActor
final class AdvancedQueryViewModel: ObservableObject {
    @Published var searchText = "太18:18-20"
    @Published var formatText = "#sec1 {book_c}{verse} {fhl} \\n {niv}\\n#sec2 {gae}"
    @Published var status = ""
    @Published var preview = ""
    @Published var isRunning = false

    // #filePath 是 Sources/AdvancedBibleQueryApp/AdvancedBibleQueryApp.swift，
    // 要往上三層（檔名 -> target 目錄 -> Sources 目錄）才會回到 advanced_bible_query_cli.rb 所在的 swift_demo 目錄
    private let scriptDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private var latestQueryID = 0

    func run() {
        guard !isRunning else { return }
        isRunning = true
        status = "查詢中..."
        latestQueryID += 1
        let queryID = latestQueryID
        let rawText = searchText
        let formatText = self.formatText

        Task.detached { [scriptDir] in
            let result = Self.runRubyCLI(
                scriptDir: scriptDir, rawText: rawText, formatText: formatText)
            await MainActor.run {
                self.isRunning = false
                guard queryID == self.latestQueryID else { return }

                switch result {
                case .success(let (status, preview)):
                    self.status = status
                    self.preview = preview
                case .failure(let error):
                    self.status = "查詢失敗: \(error.message)"
                    self.preview = ""
                }
            }
        }
    }

    private nonisolated static func runRubyCLI(scriptDir: URL, rawText: String, formatText: String)
        -> Result<(String, String), QueryError>
    {
        let cliPath = scriptDir.appendingPathComponent("advanced_bible_query_cli.rb")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ruby", cliPath.path, rawText, formatText]

        let stdout = Pipe()
        process.standardOutput = stdout

        do {
            try process.run()
        } catch {
            return .failure(QueryError(message: "無法啟動 ruby: \(error.localizedDescription)"))
        }
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let decoded = try? JSONDecoder().decode(QueryResult.self, from: data) else {
            return .failure(QueryError(message: "無法解析輸出"))
        }
        if let error = decoded.error {
            return .failure(QueryError(message: error))
        }
        return .success((decoded.status ?? "", decoded.preview ?? ""))
    }
}

struct KeynotePlaceholder: Identifiable, Hashable {
    var id: UUID = UUID()
    var placeholder: String
    var format: String
}

// 對照 src/domain/bible.rb 的 Domain::Bible::CHAPTERS，只取側欄要顯示的中文書名
let oldTestamentBooks = [
    "創世記", "出埃及記", "利未記", "民數記", "申命記", "約書亞記", "士師記", "路得記",
    "撒母耳記上", "撒母耳記下", "列王紀上", "列王紀下", "歷代志上", "歷代志下", "以斯拉記", "尼希米記",
    "以斯帖記", "約伯記", "詩篇", "箴言", "傳道書", "雅歌", "以賽亞書", "耶利米書",
    "耶利米哀歌", "以西結書", "但以理書", "何西阿書", "約珥書", "阿摩司書", "俄巴底亞書", "約拿書",
    "彌迦書", "那鴻書", "哈巴谷書", "西番雅書", "哈該書", "撒迦利亞書", "瑪拉基書",
]

let newTestamentBooks = [
    "馬太福音", "馬可福音", "路加福音", "約翰福音", "使徒行傳", "羅馬書", "哥林多前書", "哥林多後書",
    "加拉太書", "以弗所書", "腓立比書", "歌羅西書", "帖撒羅尼迦前書", "帖撒羅尼迦後書",
    "提摩太前書", "提摩太後書", "提多書", "腓利門書", "希伯來書", "雅各書", "彼得前書", "彼得後書",
    "約翰一書", "約翰二書", "約翰三書", "猶大書", "啟示錄",
]

// 章數對照 src/domain/bible.rb 的 CHAPTERS[:max]，順序跟上面兩個書名陣列一一對應
let oldTestamentChapterCounts = [
    50, 40, 27, 36, 34, 24, 21, 4,
    31, 24, 22, 25, 29, 36, 10, 13,
    10, 42, 150, 31, 12, 8, 66, 52,
    5, 48, 12, 14, 3, 9, 1, 4,
    7, 3, 3, 3, 2, 14, 4,
]

let newTestamentChapterCounts = [
    28, 16, 24, 21, 28, 16, 16, 13,
    6, 6, 4, 4, 5, 3,
    6, 4, 3, 1, 13, 5, 5, 3,
    5, 1, 1, 1, 22,
]

let bookChapterCounts: [String: Int] = Dictionary(
    uniqueKeysWithValues: zip(
        oldTestamentBooks + newTestamentBooks,
        oldTestamentChapterCounts + newTestamentChapterCounts
    )
)

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

struct AdvancedBibleQueryView: View {
    // @StateObject private var vm = AdvancedQueryViewModel()

    @State var searchDsl: String = ""
    @State var placeholders = [
        KeynotePlaceholder(placeholder: "中", format: "{中}")
    ]

    func filteredBooks(_ books: [String]) -> [String] {
        searchDsl.isEmpty ? books : books.filter { $0.contains(searchDsl) }
    }

    func binding(_ item: KeynotePlaceholder, _ keypath: WritableKeyPath<KeynotePlaceholder, String>)
        -> Binding<String>
    {
        Binding(
            get: { item[keyPath: keypath] },
            set: { newVal in
                guard let idx = placeholders.firstIndex(where: { $0.id == item.id }) else { return }
                placeholders[idx][keyPath: keypath] = newVal
            })
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section("舊約") {
                    ForEach(filteredBooks(oldTestamentBooks), id: \.self) { book in
                        BookRow(book: book, searchDsl: $searchDsl)
                    }
                }
                Section("新約") {
                    ForEach(filteredBooks(newTestamentBooks), id: \.self) { book in
                        BookRow(book: book, searchDsl: $searchDsl)
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 20)
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
                    TextField("佔位符", text: binding(item, \.placeholder))
                        .textFieldStyle(.roundedBorder)
                }
                TableColumn("格式") { item in
                    TextField("格式", text: binding(item, \.format))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .searchable(text: $searchDsl, prompt: "Find in Album")
    }

    // var body: some View {
    //     VStack(alignment: .leading, spacing: 8) {
    //         Text("搜尋經節序號").font(.caption).foregroundColor(.secondary)
    //         TextField("搜尋經節序號", text: $vm.searchText)
    //             .textFieldStyle(.roundedBorder)
    //             .onSubmit { vm.run() }

    //         Text("#<NAME_OF_REGION> 給 osascript 比對 Keynote placeholder；\\n 換行；會依用到的 token 自動查對應來源")
    //             .font(.caption)
    //             .foregroundColor(.secondary)
    //         Text("來源: {local}麥可陳 {fhl}信望愛 {niv}BibleGateway {gae}개역개정")
    //             .font(.caption)
    //             .foregroundColor(.secondary)
    //         Text("節資訊: {verse}節次 {chapter}章次 {book_c}書名中文 {book_e}書名英文 {book_k}書名韓文")
    //             .font(.caption)
    //             .foregroundColor(.secondary)

    //         TextField("格式範本", text: $vm.formatText)
    //             .textFieldStyle(.roundedBorder)
    //             .onSubmit { vm.run() }

    //         Button("查詢預覽") { vm.run() }
    //             .disabled(vm.isRunning)

    //         ProgressView(value: vm.isRunning ? nil : 0)
    //             .opacity(vm.isRunning ? 1 : 0)

    //         Text(vm.status)
    //             .font(.caption)
    //             .fixedSize(horizontal: false, vertical: true)

    //         ScrollView {
    //             Text(vm.preview)
    //                 .font(.body)
    //                 .textSelection(.enabled)
    //                 .frame(maxWidth: .infinity, alignment: .leading)
    //                 .padding(6)
    //         }
    //         .frame(minHeight: 300)
    //         .border(Color.secondary.opacity(0.3))
    //     }
    //     .padding()
    //     .frame(minWidth: 700, minHeight: 600)
    // }
}

struct AdvancedBibleQueryApp: App {
    var body: some Scene {
        WindowGroup("進階查詢") {
            AdvancedBibleQueryView()
                // 用 `swift run` 這種裸執行檔啟動時，macOS 的防搶焦點機制會讓新視窗開了也不會自動跳到前面，
                // 要手動呼叫 activate 才會把它拉到最前面、變成 key window
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}

// `swift run` 這種裸執行檔預設不是「正常前景 App」，鍵盤輸入焦點不會轉過來
// （即使畫面被 activate 拉到最前面，打字還是會跑進原本的 Terminal），要先設成 .regular
NSApplication.shared.setActivationPolicy(.regular)
AdvancedBibleQueryApp.main()

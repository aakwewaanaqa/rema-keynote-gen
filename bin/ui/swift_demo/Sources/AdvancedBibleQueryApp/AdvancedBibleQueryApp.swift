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

struct AdvancedBibleQueryView: View {
    @StateObject private var vm = AdvancedQueryViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("搜尋經節序號").font(.caption).foregroundColor(.secondary)
            TextField("搜尋經節序號", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { vm.run() }

            Text("#<NAME_OF_REGION> 給 osascript 比對 Keynote placeholder；\\n 換行；會依用到的 token 自動查對應來源")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("來源: {local}麥可陳 {fhl}信望愛 {niv}BibleGateway {gae}개역개정")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("節資訊: {verse}節次 {chapter}章次 {book_c}書名中文 {book_e}書名英文 {book_k}書名韓文")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("格式範本", text: $vm.formatText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { vm.run() }

            Button("查詢預覽") { vm.run() }
                .disabled(vm.isRunning)

            ProgressView(value: vm.isRunning ? nil : 0)
                .opacity(vm.isRunning ? 1 : 0)

            Text(vm.status)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(vm.preview)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(minHeight: 300)
            .border(Color.secondary.opacity(0.3))
        }
        .padding()
        .frame(minWidth: 700, minHeight: 600)
    }
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

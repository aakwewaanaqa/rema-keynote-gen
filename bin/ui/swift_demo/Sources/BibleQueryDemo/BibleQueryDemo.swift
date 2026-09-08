// 評估用：SwiftUI 是否能單靠「裝 Swift + 執行 script」跑起來，並跟現有 Ruby 邏輯互動。
// 執行方式：cd bin/ui/swift_demo && swift run BibleQueryDemo
//
// 對照 bin/ui/windows/lookup_bible_window.rb 的 Glimmer 版本：
// 這裡改成呼叫 swift_demo 目錄下的 bible_query_cli.rb，透過 stdout 的 JSON 交換資料，
// 而不是像 Glimmer 那樣同一個 process 內直接呼叫 Domain::BibleQuery.run(...)。

import SwiftUI
import Foundation

struct VerseRow: Identifiable {
    let id = UUID()
    let label: String
    let text: String
}

struct QueryResult: Decodable {
    let rows: [[String]]?
    let error: String?
}

struct QueryError: Error {
    let message: String
}

@MainActor
final class QueryViewModel: ObservableObject {
    @Published var query = "太18:18-20"
    @Published var rows: [VerseRow] = []
    @Published var status = ""
    @Published var isRunning = false

    // #filePath 現在是 Sources/BibleQueryDemo/BibleQueryDemo.swift，
    // 要往上三層（檔名 -> target 目錄 -> Sources 目錄）才會回到 bible_query_cli.rb 所在的 swift_demo 目錄
    private let scriptDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func run() {
        guard !isRunning else { return }
        isRunning = true
        status = "查詢中..."
        let queryText = query

        Task.detached { [scriptDir] in
            let result = Self.runRubyCLI(scriptDir: scriptDir, query: queryText)
            await MainActor.run {
                self.isRunning = false
                switch result {
                case .success(let rows):
                    self.rows = rows
                    self.status = "共 \(rows.count) 列"
                case .failure(let error):
                    self.rows = []
                    self.status = "查詢失敗: \(error.message)"
                }
            }
        }
    }

    private nonisolated static func runRubyCLI(scriptDir: URL, query: String) -> Result<[VerseRow], QueryError> {
        let cliPath = scriptDir.appendingPathComponent("bible_query_cli.rb")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ruby", cliPath.path, query]

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
        let rows = (decoded.rows ?? []).map { VerseRow(label: $0[0], text: $0.count > 1 ? $0[1] : "") }
        return .success(rows)
    }
}

struct ContentView: View {
    @StateObject private var vm = QueryViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("查聖經（SwiftUI 評估版）").font(.headline)

            HStack {
                TextField("搜尋經節序號", text: $vm.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { vm.run() }

                Button(vm.isRunning ? "查詢中..." : "查詢") { vm.run() }
                    .disabled(vm.isRunning)
            }

            Text(vm.status).foregroundColor(.secondary).font(.caption)

            List(vm.rows) { row in
                HStack(alignment: .top) {
                    Text(row.label).bold().frame(width: 120, alignment: .leading)
                    Text(row.text)
                }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

NSApplication.shared.setActivationPolicy(.regular)
DemoApp.main()

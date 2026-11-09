import AppKit
import SwiftUI

// 批次把歌詞資料夾裡的 .txt 套進 Keynote 範本、匯出 PNG（以前是 bin/main.rb，用 osascript 跳檔案對話框）。
// 輸出到 <歌詞資料夾>/<歌名>/<段落名稱>/<段落名稱>.001.png，歌詞檔格式見 README
struct LyricsKeynoteView: View {
    @AppStorage("lyricsKeynoteTemplatePath") private var templatePath = ""
    @AppStorage("lyricsKeynoteFolderPath") private var folderPath = ""
    @State private var log: [String] = []
    @State private var isRunning = false

    private var lyricsFileCount: Int {
        folderPath.isEmpty ? 0 : LyricsBatchGenerator.lyricsFiles(in: URL(fileURLWithPath: folderPath)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pathRow(title: "Keynote 範本", path: templatePath, placeholder: "尚未選擇 .key 檔案") {
                if let url = pickTemplate() { templatePath = url.path }
            }
            pathRow(title: "歌詞資料夾", path: folderPath, placeholder: "尚未選擇資料夾") {
                if let url = pickFolder() { folderPath = url.path }
            }
            if !folderPath.isEmpty {
                Text("資料夾內有 \(lyricsFileCount) 個 .txt 歌詞檔")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    run()
                } label: {
                    Label("產生投影片", systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRunning || templatePath.isEmpty || folderPath.isEmpty)

                if isRunning { ProgressView().controlSize(.small) }
                Spacer()
                Button("打開歌詞資料夾") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: folderPath))
                }
                .disabled(folderPath.isEmpty)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(log.joined(separator: "\n"))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
                .onChange(of: log.count) { _ in proxy.scrollTo("bottom") }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }

    private func pathRow(title: String, path: String, placeholder: String, choose: @escaping () -> Void) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Text(path.isEmpty ? placeholder : path)
                .foregroundStyle(path.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("選擇…", action: choose).disabled(isRunning)
        }
    }

    private func pickTemplate() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "選擇模板 .key 檔案"
        panel.allowedContentTypes = [.init(filenameExtension: "key")].compactMap { $0 }
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = RemaPaths.templates
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "選擇歌詞資料夾"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func run() {
        guard !isRunning else { return }
        isRunning = true
        log = []
        let template = URL(fileURLWithPath: templatePath)
        let folder = URL(fileURLWithPath: folderPath)

        // 每個段落都要等 osascript 叫 Keynote 開檔、匯出，整批會跑很久，丟到背景，log 一行一行送回 main thread
        Task.detached {
            do {
                try LyricsBatchGenerator.run(template: template, lyricsFolder: folder) { line in
                    Task { @MainActor in log.append(line) }
                }
            } catch {
                await MainActor.run { log.append("失敗：\(error.localizedDescription)") }
            }
            await MainActor.run { isRunning = false }
        }
    }
}

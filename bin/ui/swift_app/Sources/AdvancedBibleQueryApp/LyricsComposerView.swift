import AppKit
import SwiftUI
import UniformTypeIdentifiers

// 對照 web/lyric-composer.html 的五個區塊：1 解析混合語言 TXT、2 匯入單語歌詞、
// 3 逐頁檢查與修正、4 設定輸出格式、5 預覽與下載。邏輯都搬進 LyricsComposerStore，
// 這支只負責排版跟檔案存取（AppKit 的 NSOpenPanel/NSSavePanel，跟 BibleSearchResultView
// 選範本/輸出資料夾用同一種模式）。
struct LyricsComposerView: View {
    @StateObject private var store = LyricsComposerStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                mixedSection
                singleLanguageSection
                rowsSection
                outputSettingsSection
                previewSection
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 640)
        .navigationTitle("歌詞整理")
    }

    // MARK: - Section 1

    private var mixedSection: some View {
        GroupBox("1. 解析既有多語歌詞 TXT") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("貼上或匯入混合語言 TXT").font(.headline)
                    Spacer()
                    Button("匯入檔案") { importMixedFile() }
                }
                TextEditor(text: $store.mixedSourceText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("來源格式").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $store.mixedFormat) {
                            ForEach(MixedFormatPreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .labelsHidden()
                    }
                    langPicker("第一行", selection: $store.mixedLang1, includeNone: true)
                    langPicker("第二行", selection: $store.mixedLang2, includeNone: true)
                    langPicker("第三行", selection: $store.mixedLang3, includeNone: true)
                }

                HStack {
                    Button("固定行數解析並拆解") { store.parseMixed() }
                        .buttonStyle(.borderedProminent)
                    Text("CE／CK 每 2 行一頁；CEK／CKE 每 3 行一頁。空白行會自動忽略。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Text(store.parseStatus)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)

                Divider()

                Text("拆解結果").font(.headline)
                Text("解析 CE 後可複製 EN；再解析 CK 並帶入單語欄位，最後貼回 EN，即可組成 CEK。")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 12) {
                    splitColumn(title: "中文 CN", text: store.splitCN)
                    splitColumn(title: "英文 EN", text: store.splitEN)
                    splitColumn(title: "韓文 KR", text: store.splitKR)
                }

                Button("將拆解結果帶入單語欄位") { store.sendSplitToSingle() }
                    .buttonStyle(.bordered)
            }
            .padding(10)
        }
    }

    private func splitColumn(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                Button("複製") { copyToClipboard(text) }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
            TextEditor(text: .constant(text))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }

    // MARK: - Section 2

    private var singleLanguageSection: some View {
        GroupBox("2. 匯入單語歌詞") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    singleColumn(title: "中文 CN（基準）", text: $store.srcCN, lang: .cn)
                    singleColumn(title: "英文 EN", text: $store.srcEN, lang: .en)
                    singleColumn(title: "韓文 KR", text: $store.srcKR, lang: .kr)
                }
                HStack {
                    Button("建立／重新對齊") { store.buildRows() }
                        .buttonStyle(.borderedProminent)
                    Text("每一行視為一頁中的一個語言欄位。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
        }
    }

    private func singleColumn(title: String, text: Binding<String>, lang: LyricLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                Button("匯入檔案") { importSingleFile(into: text) }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
            TextEditor(text: text)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }

    // MARK: - Section 3

    private var rowsSection: some View {
        GroupBox("3. 逐頁檢查與修正") {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.status)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)

                HStack {
                    Button("新增一頁") { store.addRow() }
                    Button("儲存工作檔 JSON") { saveProjectJSON() }
                    Button("載入工作檔 JSON") { loadProjectJSON() }
                    Spacer()
                    Text("\(store.rows.count) 頁").font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    HStack {
                        Text("頁").frame(width: 36)
                        Text("CN").frame(maxWidth: .infinity, alignment: .leading)
                        Text("EN").frame(maxWidth: .infinity, alignment: .leading)
                        Text("KR").frame(maxWidth: .infinity, alignment: .leading)
                        Text("").frame(width: 44)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 4)

                    Divider()

                    ForEach(Array(store.rows.enumerated()), id: \.element.id) { index, row in
                        HStack(alignment: .top) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 36)
                                .padding(.top, 6)
                            rowField(row: row, lang: .cn)
                            rowField(row: row, lang: .en)
                            rowField(row: row, lang: .kr)
                            Button {
                                store.deleteRow(id: row.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .foregroundColor(.red)
                            .buttonStyle(.borderless)
                            .frame(width: 44)
                            .padding(.top, 6)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        Divider()
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }
            .padding(10)
        }
    }

    private func rowField(row: LyricRow, lang: LyricLanguage) -> some View {
        TextEditor(text: rowBinding(id: row.id, lang: lang))
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
    }

    private func rowBinding(id: UUID, lang: LyricLanguage) -> Binding<String> {
        Binding(
            get: { store.rows.first { $0.id == id }?[lang] ?? "" },
            set: { newValue in
                guard let idx = store.rows.firstIndex(where: { $0.id == id }) else { return }
                store.rows[idx][lang] = newValue
            })
    }

    // MARK: - Section 4

    private var outputSettingsSection: some View {
        GroupBox("4. 設定輸出格式") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ForEach(OutputPreset.allCases) { preset in
                        Button(preset.code) { store.applyOutputPreset(preset) }
                            .buttonStyle(.bordered)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    labeledPicker("第一行") { langPickerContent($store.lang1, includeNone: true) }
                    labeledPicker("第二行") { langPickerContent($store.lang2, includeNone: true) }
                    labeledPicker("第三行") { langPickerContent($store.lang3, includeNone: true) }
                    labeledPicker("輸出類型") {
                        Picker("", selection: $store.outputType) {
                            ForEach(LyricsOutputType.allCases) { Text($0.label).tag($0) }
                        }.labelsHidden()
                    }
                    labeledPicker("空翻譯處理") {
                        Picker("", selection: $store.emptyMode) {
                            ForEach(EmptyTranslationMode.allCases) { Text($0.label).tag($0) }
                        }.labelsHidden()
                    }
                    labeledPicker("輸出檔名") {
                        TextField("", text: $store.filename).textFieldStyle(.roundedBorder)
                    }
                    labeledPicker("換行格式") {
                        Picker("", selection: $store.lineEnding) {
                            ForEach(LyricsLineEnding.allCases) { Text($0.label).tag($0) }
                        }.labelsHidden()
                    }
                }

                Text("「Rema 用 TXT」會依目前選擇的語言數量自動產生 line，並依語言順序產生 placeholders。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }

    private func labeledPicker<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func langPicker(_ title: String, selection: Binding<LyricLanguage?>, includeNone: Bool) -> some View {
        labeledPicker(title) { langPickerContent(selection, includeNone: includeNone) }
    }

    private func langPickerContent(_ selection: Binding<LyricLanguage?>, includeNone: Bool) -> some View {
        Picker("", selection: selection) {
            ForEach(LyricLanguage.allCases) { lang in
                Text(lang.displayName).tag(Optional(lang))
            }
            if includeNone {
                Text("不使用").tag(LyricLanguage?.none)
            }
        }
        .labelsHidden()
    }

    // MARK: - Section 5

    private var previewSection: some View {
        let output = store.getOutput()
        return GroupBox("5. 預覽與下載") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("下載 TXT") { downloadOutput(output) }
                        .buttonStyle(.borderedProminent)
                    Button("複製輸出內容") { copyToClipboard(output.text) }
                    Spacer()
                    Text("\(output.slideCount) slides")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(99)
                }
                ScrollView {
                    Text(output.text.isEmpty ? "尚無輸出內容" : output.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 180, maxHeight: 360)
                .background(Color.black.opacity(0.85))
                .cornerRadius(8)
            }
            .padding(10)
        }
    }

    // MARK: - 檔案存取

    private func readTextFile(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private func importMixedFile() {
        let panel = NSOpenPanel()
        panel.title = "選擇混合語言 TXT"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .text]
        guard panel.runModal() == .OK, let url = panel.url, let text = readTextFile(url) else { return }
        store.mixedSourceText = text
    }

    private func importSingleFile(into binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.title = "選擇歌詞 TXT"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .text]
        guard panel.runModal() == .OK, let url = panel.url, let text = readTextFile(url) else { return }
        binding.wrappedValue = text
    }

    private func saveProjectJSON() {
        guard let data = try? store.exportProjectJSON() else { return }
        let panel = NSSavePanel()
        panel.title = "儲存工作檔"
        panel.nameFieldStringValue = "lyrics-project.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    private func loadProjectJSON() {
        let panel = NSOpenPanel()
        panel.title = "載入工作檔"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        try? store.loadProjectJSON(data)
    }

    private func downloadOutput(_ output: LyricsOutput) {
        guard !output.text.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "下載 TXT"
        panel.nameFieldStringValue = store.filename.isEmpty ? "lyrics.txt" : store.filename
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // 跟 html 版一致，開頭加 UTF-8 BOM（ProPresenter 讀多語文字檔比較不會亂碼）
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(output.text.utf8))
        try? data.write(to: url)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

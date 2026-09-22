import SwiftUI

// App 開啟後的第一個畫面：選要「查經文」還是「歌詞整理」，各自開獨立視窗
// （WindowGroup id "bible-query" / "lyrics-composer"，見 AdvancedBibleQueryApp.swift）。
// 這個入口視窗選完之後不會自動關閉，方便之後想切換另一項功能時直接回來點。
struct HomeView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Text("Rema 工具").font(.largeTitle.bold())
                Text("選擇要處理的項目").foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                optionCard(
                    title: "查經文",
                    subtitle: "查詢經文、套範本產生 Keynote",
                    icon: "book.closed"
                ) {
                    openWindow(id: "bible-query")
                }
                optionCard(
                    title: "歌詞整理",
                    subtitle: "解析多語歌詞、逐頁對齊、輸出 TXT",
                    icon: "music.note.list"
                ) {
                    openWindow(id: "lyrics-composer")
                }
            }
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 320)
    }

    private func optionCard(
        title: String, subtitle: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .frame(width: 190, height: 170)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

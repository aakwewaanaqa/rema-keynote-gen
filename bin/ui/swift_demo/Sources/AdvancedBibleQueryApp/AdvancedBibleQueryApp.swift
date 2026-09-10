// SwiftUI 版的進階查詢視窗，對照 bin/ui/windows/advanced_bible_query_window.rb（Glimmer LibUI 版）。
// 查詢/範本邏輯不重寫，沿用 swift_demo 目錄下的 advanced_bible_query_cli.rb（透過 Process 呼叫 Ruby，JSON 交換資料），
// 這支只負責 UI 跟事件處理。
// 執行方式：cd bin/ui/swift_demo && swift run AdvancedBibleQueryApp

import AppKit
import SwiftUI

struct AdvancedBibleQueryApp: App {
    @StateObject private var resultStore = BibleSearchResultStore()

    var body: some Scene {
        WindowGroup("進階查詢") {
            AdvancedBibleQueryView()
                .environmentObject(resultStore)
                // 用 `swift run` 這種裸執行檔啟動時，macOS 的防搶焦點機制會讓新視窗開了也不會自動跳到前面，
                // 要手動呼叫 activate 才會把它拉到最前面、變成 key window
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }

        // 用獨立視窗（不是 popover/sheet）顯示某一筆查詢結果的經文；
        // 傳的是 UUID 而不是整個 BibleSearchResult，實際內容從 resultStore 裡找
        WindowGroup("查詢結果", for: UUID.self) { $resultID in
            BibleSearchResultView(resultID: resultID)
                .environmentObject(resultStore)
        }
    }
}

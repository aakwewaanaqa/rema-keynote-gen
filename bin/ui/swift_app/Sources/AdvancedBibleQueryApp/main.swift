import AppKit

// `swift run` 這種裸執行檔預設不是「正常前景 App」，鍵盤輸入焦點不會轉過來
// （即使畫面被 activate 拉到最前面，打字還是會跑進原本的 Terminal），要先設成 .regular
NSApplication.shared.setActivationPolicy(.regular)
AdvancedBibleQueryApp.main()

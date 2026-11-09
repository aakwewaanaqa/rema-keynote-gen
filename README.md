# Rema Keynote 產生器

從歌詞 `.txt` 自動批次產生 Keynote 投影片圖片。

## 需求

- macOS 13 Ventura 以上（Apple Silicon 與 Intel Mac 都可以）
- Keynote（App Store）
- 網路連線（查詢經文用）

## 安裝：依 macOS 版本選擇

先到「 → 關於這台 Mac」看 macOS 版本。

| macOS 版本 | 安裝方式 | 更新方式 |
| --- | --- | --- |
| 13.5 以上（Ventura 13.5、Sonoma、Sequoia、Tahoe…） | `install.command`（建議） | 雙擊 `start.command` 自動更新 |
| 13.0 ～ 13.4，或裝不了開發工具的電腦 | 下載 [Release](https://github.com/aakwewaanaqa/rema-keynote-gen/releases/latest) | 回 Release 頁面重新下載 |
| 12 Monterey 以下 | 不支援，請先升級 macOS | — |

> `install.command` 會在本機編譯 App，需要 Swift 5.9 以上的 Command Line Tools，
> 而這一版只能裝在 macOS 13.5 以上；比較舊的系統請直接下載已經編好的 Release。

### 新版 macOS：用 `install.command`

1. 分享 `install.command` 給同工，雙擊執行
   （如果出現「無法打開」，按右鍵 → 打開；或到「系統設定 → 隱私權與安全性」按「強制打開」）
2. 第一次執行會跳出安裝「Command Line Tools」的視窗，按「安裝」，裝完後**重新雙擊** `install.command`
3. 程式會下載到 `~/Documents/rema-keynote-gen`、編譯完成後自動開啟 App
   （在 Finder 按 `Cmd + Shift + O` 可以快速開啟文件夾）
4. 之後每次使用：雙擊資料夾裡的 `start.command`，會自動更新到最新版、重新編譯並開啟 App

### 舊版 macOS：用 Release

1. 打開 [Release 頁面](https://github.com/aakwewaanaqa/rema-keynote-gen/releases/latest)，下載 `AdvancedBibleQueryApp-x.y.z.zip`
2. 雙擊解壓縮，把 `AdvancedBibleQueryApp.app` 拖進「應用程式」資料夾
3. 雙擊打開就能用（已經過 Apple 公證，不會跳安全性警告）

Release 版不會自動更新，有新版本時請回到 Release 頁面重新下載。

> 不論哪種方式，第一次產生 Keynote 時 macOS 會詢問是否允許控制 Keynote，請按「好」。

## 執行

App 首頁有三個功能：

- **查經文**：查詢經文（信望愛、NIV/NKJV/KJV、개역개정），套 placeholder 範本產生 Keynote
- **歌詞整理**：解析多語歌詞、逐頁對齊，輸出 ProPresenter TXT 或下面格式的歌詞檔
- **歌詞產生 Keynote**：選範本與歌詞資料夾，把資料夾裡每個 `.txt` 套進範本、匯出 PNG

## 開發

整個專案都是 Swift（SwiftPM 套件在 `bin/ui/swift_app`），不需要 Ruby。

```
make run.ui            # 編譯、打包並開啟 App
make do.test.all       # 跑單元測試
make do.test.network   # 連同會打外部聖經網站的測試一起跑
```

- `Sources/RemaCore`：查詢語法解析、各聖經來源、範本代換、Keynote（osascript）、歌詞解析
- `Sources/AdvancedBibleQueryApp`：SwiftUI 介面
- 本機聖經來源（麥可陳 cuv2）讀的是專案根目錄下的 `bible_src`，需要另外 `git clone https://github.com/michaelchanwahyan/bible_src.git`

---

## 歌詞檔格式

副檔名 `.txt`，檔名即歌曲名稱（輸出資料夾會用這個名字）。

### 設定（檔案最前面）

```
#! line=3
#! placeholders=kr,cn,en
```

- `line` — 每張投影片幾行歌詞
- `placeholders` — 模板裡佔位符的名稱，順序對應第一行、第二行……

### 段落

```
# Chorus
（歌詞）
# end Chorus

# Verse
（歌詞）
# end Verse
```

- `# 段落名稱` 開始，`# end 段落名稱` 結束
- 每個段落會輸出到獨立資料夾
- 空行用來分隔投影片，不會出現在內容裡

### 完整範例

```
#! line=3
#! placeholders=kr,cn,en

# Chorus

영광의 주님
榮光的 主神
You are Glorious

예수 영광의 주님
耶穌 榮光的 主神
Jesus You are glorious

# end Chorus

# Verse

주와 같은 분은 없네
世上無人 與你同等
There's no one can stand against.

# end Verse
```

輸出結構：

```
歌曲名稱/
  Chorus/
    Chorus.001.png
    Chorus.002.png
  Verse/
    Verse.001.png
```

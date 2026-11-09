# Rema Keynote 產生器

從歌詞 `.txt` 自動批次產生 Keynote 投影片圖片。

## 需求

- macOS
- Keynote（App Store）
- Git（第一次安裝時系統會自動提示）

## 安裝

分享 `install.command` 給同工，雙擊執行，照指示操作即可。
安裝完成後 `~/Documents/rema-keynote-gen` 會出現程式資料夾。
在 Finder 按 `Cmd + Shift + O` 可以快速開啟文件夾。

## 執行

雙擊 `start.command`，每次執行會自動更新到最新版、重新編譯並開啟 App。

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

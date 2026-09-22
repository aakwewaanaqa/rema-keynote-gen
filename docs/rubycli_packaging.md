# 把 ruby 直譯器打包進 swift_app（rubycli / tebako）

## 這是什麼

`bin/ui/swift_app/AdvancedBibleQueryApp.app` 原本執行 `advanced_bible_query_cli.rb` /
`generate_keynote_cli.rb` 靠的是 `~/.rbenv/shims/ruby`，只能在裝好這套開發環境的機器上跑。
`rubycli` 是用 [tebako](https://github.com/tamatebako/tebako) 把 ruby 直譯器、`nokogiri`
gem（含靜態編譯的 libxml2/libxslt/libgumbo）、還有 `src/`、`bible_src/`、兩支 CLI 腳本全部
壓成的**單一可執行檔**，不依賴使用者機器上裝了什麼 ruby，`package_app.sh` 會自動把它包進
`.app/Contents/Resources/`，讓整個 app 變成可以 AirDrop 給別人、對方直接雙擊就能跑的獨立 bundle。

## 平常怎麼用

- **`./package_app.sh`**：日常開發用，重建 Swift app。如果 `rubycli` 存在就會一併包進去；
  沒有的話 app 仍可正常運作，只是退回 `~/.rbenv/shims/ruby`（只能在這台機器跑）。
- **`./build_rubycli.sh`**：只有動到 **ruby 那邊**的程式碼（`src/`、`bible_src/`、
  `advanced_bible_query_cli.rb`、`generate_keynote_cli.rb`）之後，想產生「能發佈給別人」的版本時
  才需要重跑。大概要幾分鐘（第一次要下載 prebuilt runtime，需要網路）。跑完再跑一次
  `./package_app.sh` 把新的 `rubycli` 包進 app。

`rubycli` 本身沒有進 git（在 `.gitignore` 裡，檔案有 70+ MB 又是機器產物）。

## ⚠️ 重要：這台機器動過的環境（不在 git 版控範圍內）

2026-09-22 在這台機器上第一次打通 `build_rubycli.sh` 時，這台機器跑的是 **macOS 26.6.2 +
Xcode 27**（非常新的 beta 組合），tebako 從原始碼建置 ruby 的過程在這個組合下踩到好幾個
環境層級的坑。以下改動都是動到**這台機器全域安裝的東西**（brew、rbenv 全域 gem、
tebako gem 自己的檔案），跟這個 git repo 無關，**換一台機器、或之後升級 `tebako` gem
版本，很可能要重新套用一次**。

### 1. 裝了幾個 brew 套件

```
brew install cmake bison flex automake zlib
```
（`bison`/`flex`/`zlib` 是 keg-only，tebako 建置 ruby 時需要它們在 PATH 上：
`export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH"`）

### 2. 裝了 tebako gem

```
gem install tebako
tebako setup   # 第一次要編一份完整的 ruby toolchain，會跑很久
```

### 3. Patch 了 tebako gem 自己的兩個檔案

這兩個 patch 都是手動改在
`~/.rbenv/versions/3.4.6/lib/ruby/gems/3.4.0/gems/tebako-0.15.9/` 底下，**gem 更新或重裝
就會被蓋掉**：

**(a) `CMakeLists.txt`** — 排除 `ext/fiddle`（darwin 分支，約在 `elseif("${OSTYPE_TXT}"
MATCHES "^darwin.*")` 底下）：

```cmake
elseif("${OSTYPE_TXT}" MATCHES "^darwin.*")
  set(IS_DARWIN ON)
  # fiddle 的 mkmf have_func 探測在 macOS 26 + Xcode 27 SDK 上會無限卡死（0% CPU，
  # clang -E 處理 conftest.c 永遠不回傳），原因不明，這個專案本來就用不到 FFI，直接排除
  set(RUBY_WITHOUT_EXT "dbm,win32,win32ole,fiddle,-test-/*")
endif()
```

**(b) `lib/ruby/3.3.0/mkmf.rb`**（打包出來的 ruby 自己的 mkmf.rb，在
`~/.tebako/o/s/lib/ruby/3.3.0/mkmf.rb` 和 `~/.tebako/deps/stash_3.3.7/lib/ruby/3.3.0/mkmf.rb`
兩個地方都要改，後者是持久化的 stash，`tebako press` 每次都從那邊複製出乾淨環境）：

第 648 行，`try_cppflags` 方法：

```ruby
# 改之前
def try_cppflags(flags, opts = {})
  try_header(MAIN_DOES_NOTHING, flags, {:werror => true}.update(opts))
end

# 改之後
def try_cppflags(flags, opts = {})
  try_header(MAIN_DOES_NOTHING, flags, {:werror => false}.update(opts))
end
```

### 4. Ruby 原始碼本身也 patch 過一次（但這個不用手動維護）

`~/.tebako/deps/src/_ruby_3.3.7/io.c`（連同 tebako 自己維護的 `.old` 備份）曾經手動 patch
過，讓 `pipe2`/`dup3` 在 Apple 平台上直接跳過（macOS 26 + Xcode 27 SDK 的 weak-link bug）。
**這個不用擔心**：只要 `tebako setup` 成功跑完一次，這個修正就已經編進
`~/.tebako/deps/stash_3.3.7` 這份「已建置好的 ruby」裡了，之後 `tebako press` 都是直接複製
這份 stash，不會重新觸發這個 bug。只有在 `~/.tebako` 整個被清掉、要重新跑一次完整
`tebako setup` 時，才需要重新套用這個 patch（見下方「從零開始重建環境」）。

## 從零開始重建環境（新機器 / `~/.tebako` 被清掉時）

如果 `./build_rubycli.sh` 突然又炸開、錯誤訊息長得像下面這些，代表 `~/.tebako` 的環境
不見了或不完整，需要照順序重來一次：

1. **`miniruby` 一啟動就 segfault**（`rb_cloexec_pipe` 相關的 crash，或
   `builtin_binary.inc Segmentation fault`）→ 套用上面「(4) ruby 原始碼」那個 io.c patch：

   ```bash
   cd ~/.tebako/deps/src/_ruby_3.3.7
   sed -i '' 's/^#ifdef HAVE_PIPE2$/#if defined(HAVE_PIPE2) \&\& !(defined(__APPLE__) \&\& defined(__MACH__))/' io.c
   sed -i '' 's/^#if defined(HAVE_DUP3) && defined(O_CLOEXEC)$/#if defined(HAVE_DUP3) \&\& defined(O_CLOEXEC) \&\& !(defined(__APPLE__) \&\& defined(__MACH__))/' io.c
   cp io.c io.c.old
   ```

   然後不要重跑 `tebako setup`（它每次都會整個清掉重新解壓源碼，剛剛的 patch 又會消失），
   改成直接繼續底層的 make：

   ```bash
   export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH"
   cd ~/.tebako/o && make -f Makefile setup
   ```

2. **`tebako press` 一開始就狂洗環境**（印出 `Cleaning tebako packaging environment` /
   `CMake cache version was not recognized`）→ `~/.tebako/deps/.environment.version` 這個
   版本快取檔不見或內容不對，補上：

   ```bash
   printf '0.15.9 at /Users/ponito/.rbenv/versions/3.4.6/lib/ruby/gems/3.4.0/gems/tebako-0.15.9\n' \
     > ~/.tebako/deps/.environment.version
   ```

   （`0.15.9` 要換成實際裝的 tebako 版本；`.../gems/tebako-0.15.9` 那段要換成 `gem which
   tebako` 或 `gem env` 查到的實際安裝路徑。）

3. **`bundle install` 説找不到 nokogiri**（`Could not find gem 'nokogiri' in locally
   installed gems`）→ 檢查 `.tebako_root/Gemfile` 第一行有沒有 `source
   "https://rubygems.org"`（`build_rubycli.sh` 已經會自動補上，如果還是失敗代表這個
   自動補的邏輯本身出了問題，去檢查 `build_rubycli.sh` 裡加 source 那段）。

4. **nokogiri 編譯時說 `nokogiri_gumbo.h` 找不到**（明明檔案在硬碟上）→ 上面「(3b)
   mkmf.rb」那個 patch 沒套用或又被蓋掉了，重新套用（`~/.tebako/o/s/...` 和
   `~/.tebako/deps/stash_3.3.7/...` 兩份都要改）。

5. **任何長時間編譯指令卡在 0% CPU 不動** → 不要用會把指令包進背景執行的工具機制去跑
   `make`/`tebako` 相關指令，那個機制會跟 GNU Make 的 jobserver（用 fd 3、4 溝通平行編譯
   的工作權杖）搶檔案描述符造成死鎖。改用 shell 原生的 `(指令 &)` 丟到背景，再用一般的
   前景指令（`ps`、`tail log`）回頭檢查進度。

## 相關檔案

- `bin/ui/swift_app/build_rubycli.sh` — 產生 `rubycli` 的腳本
- `bin/ui/swift_app/package_app.sh` — 打包 app、偵測並塞入 `rubycli`
- `bin/ui/swift_app/cli_entry.rb` — `rubycli` 的進入點，依 `query`/`generate` 分派到對應的
  CLI 腳本
- `bin/ui/swift_app/Sources/AdvancedBibleQueryApp/QueryModels.swift` 的
  `configureRubyProcess` — Swift 端優先找 `.app/Contents/Resources/rubycli`，找不到才退回
  `~/.rbenv/shims/ruby` + 原始碼樹裡的 `.rb`

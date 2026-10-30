#!/bin/bash

REPO_URL="https://github.com/aakwewaanaqa/rema-keynote-gen.git"
INSTALL_DIR="$HOME/Documents/rema-keynote-gen"
SWIFT_APP_DIR="$INSTALL_DIR/bin/ui/swift_app"

# Package.swift 寫的是 swift-tools-version: 5.9，比這個舊的 Swift 編不過
MIN_SWIFT_MAJOR=5
MIN_SWIFT_MINOR=9

fail() {
  echo ""
  echo "$1"
  echo ""
  read -p "按 Enter 關閉..."
  exit 1
}

clear
echo "================================"
echo "  Rema Keynote 產生器 — 安裝"
echo "================================"
echo ""

# ── 1. Xcode Command Line Tools ──────────────────────────────
# git、swift（SwiftPM）、clang、macOS SDK 都在這包裡，不需要裝完整的 Xcode.app。
# Homebrew 安裝程式其實也會自己裝，但它是無聲地在背景跑 softwareupdate、要等很久，
# 先在這裡用系統的安裝視窗裝好，使用者看得到進度。
echo "[1/5] 檢查開發工具（Command Line Tools）..."
if ! xcode-select -p &>/dev/null; then
  xcode-select --install &>/dev/null
  fail "請在剛才跳出的視窗按『安裝』（大約需要 5～15 分鐘）。
安裝完成後，請重新雙擊這個檔案。"
fi

# ── 2. Homebrew ──────────────────────────────────────────────
# 系統內建的 Ruby 是 SIP 保護的唯讀目錄，裝不了 nokogiri 這種原生擴充 gem，
# 所以一律改用 Homebrew 的 Ruby。
echo "[2/5] 檢查 Homebrew..."

# 每台 Mac 開新的 Terminal session 時，/opt/homebrew/bin（Apple Silicon）或 /usr/local/bin
# （Intel）不一定在 PATH 上——官方安裝完會請使用者自己把 `brew shellenv` 加進 shell 設定檔，
# 但這個腳本是雙擊執行、不會讀那份設定檔，所以這裡自己找路徑、手動 eval 一次
load_brew() {
  for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$brew_path" ]; then
      eval "$("$brew_path" shellenv)"
      return
    fi
  done
}

load_brew
if ! command -v brew &>/dev/null; then
  echo "還沒有安裝 Homebrew，正在自動安裝（會要你輸入 Mac 的登入密碼）..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew
  command -v brew &>/dev/null || fail "Homebrew 安裝好像沒有成功，請重新雙擊這個檔案再試一次。"
fi

# ── 3. 下載／更新程式 ─────────────────────────────────────────
echo "[3/5] 下載程式..."
ALREADY_INSTALLED=false
if [ -d "$INSTALL_DIR/.git" ]; then
  ALREADY_INSTALLED=true
  echo "已安裝過了，更新到最新版..."
  (cd "$INSTALL_DIR" && git pull) || echo "⚠️  無法更新（請確認網路），用目前版本繼續。"
else
  git clone "$REPO_URL" "$INSTALL_DIR" || fail "下載失敗，請確認網路後重新雙擊這個檔案。"
fi

chmod +x "$INSTALL_DIR/start.command"

# ── 4. Ruby 與套件 ────────────────────────────────────────────
echo "[4/5] 檢查 Ruby 與套件..."
BREW_RUBY_PREFIX="$(brew --prefix ruby 2>/dev/null)"
if [ -z "$BREW_RUBY_PREFIX" ] || [ ! -x "$BREW_RUBY_PREFIX/bin/ruby" ]; then
  echo "正在安裝 Ruby（透過 Homebrew，第一次會花幾分鐘）..."
  brew install ruby || fail "Ruby 安裝失敗，請重新雙擊這個檔案再試一次。"
  BREW_RUBY_PREFIX="$(brew --prefix ruby)"
fi

(cd "$INSTALL_DIR" && "$BREW_RUBY_PREFIX/bin/bundle" install) || fail "套件安裝失敗，請重新雙擊這個檔案再試一次。"

# ── 5. 編譯 swift_app ─────────────────────────────────────────
echo "[5/5] 編譯 App（第一次會花幾分鐘）..."

# xcode-select 指到還沒同意授權條款的 Xcode.app 時，swift 會直接失敗，這裡先擋下來講清楚
SWIFT_VERSION_OUTPUT="$(swift --version 2>&1)" || fail "找不到可以用的 swift。
如果有裝 Xcode，請先打開 Xcode 一次並同意授權條款，再重新雙擊這個檔案。"

# 輸出長得像「Apple Swift version 6.0.3 (swiftlang-...)」
read -r SWIFT_MAJOR SWIFT_MINOR <<<"$(echo "$SWIFT_VERSION_OUTPUT" | sed -n 's/.*Swift version \([0-9]*\)\.\([0-9]*\).*/\1 \2/p' | head -1)"
if [ -z "$SWIFT_MAJOR" ] \
  || [ "$SWIFT_MAJOR" -lt "$MIN_SWIFT_MAJOR" ] \
  || { [ "$SWIFT_MAJOR" -eq "$MIN_SWIFT_MAJOR" ] && [ "$SWIFT_MINOR" -lt "$MIN_SWIFT_MINOR" ]; }; then
  fail "Swift 版本太舊（目前：${SWIFT_MAJOR:-?}.${SWIFT_MINOR:-?}，需要 ${MIN_SWIFT_MAJOR}.${MIN_SWIFT_MINOR} 以上）。
請到「系統設定 → 一般 → 軟體更新」更新 macOS 與 Command Line Tools 後再試一次。"
fi

"$SWIFT_APP_DIR/package_app.sh" || fail "App 編譯失敗，請把上面的訊息截圖傳給維護的人。"

echo ""
echo "================================"
if [ "$ALREADY_INSTALLED" = true ]; then
  echo "  更新完成！"
else
  echo "  安裝完成！"
  echo "  文件夾出現了 rema-keynote-gen 資料夾"
fi
echo "  App 位置：bin/ui/swift_app/AdvancedBibleQueryApp.app"
echo "  （終端機版本仍然可以雙擊 start.command 執行）"
echo "================================"
echo ""
open "$SWIFT_APP_DIR/AdvancedBibleQueryApp.app"
read -p "按 Enter 關閉..."

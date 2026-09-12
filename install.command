#!/bin/bash

REPO_URL="https://github.com/aakwewaanaqa/rema-keynote-gen.git"
INSTALL_DIR="$HOME/Documents/rema-keynote-gen"

clear
echo "================================"
echo "  Rema Keynote 產生器 — 安裝"
echo "================================"
echo ""

echo "檢查開發工具..."
if ! git --version &>/dev/null; then
  echo ""
  echo "請在剛才跳出的視窗按『安裝』。"
  echo "安裝完成後，請重新雙擊這個檔案。"
  echo ""
  read -p "按 Enter 關閉..."
  exit 1
fi

# 系統內建的 Ruby 是 SIP 保護的唯讀目錄，裝不了 nokogiri 這種原生擴充 gem，
# 所以一律改用 Homebrew 的 Ruby。
echo "檢查 Homebrew..."

# 每台 Mac 開新的 Terminal session 時，/opt/homebrew/bin（Apple Silicon）或 /usr/local/bin
# （Intel）不一定在 PATH 上——官方安裝完會請使用者自己把 `brew shellenv` 加進 shell 設定檔，
# 但這個腳本是雙擊執行、不會讀那份設定檔，所以這裡自己找路徑、手動 eval 一次
for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [ -x "$brew_path" ]; then
    eval "$("$brew_path" shellenv)"
    break
  fi
done

if ! command -v brew &>/dev/null; then
  echo "還沒有安裝 Homebrew，正在自動安裝（會跳出來要你輸入 Mac 的登入密碼）..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$brew_path" ]; then
      eval "$("$brew_path" shellenv)"
      break
    fi
  done

  if ! command -v brew &>/dev/null; then
    echo ""
    echo "Homebrew 安裝好像沒有成功，請重新雙擊這個檔案再試一次。"
    echo ""
    read -p "按 Enter 關閉..."
    exit 1
  fi
fi

ALREADY_INSTALLED=false
if [ -d "$INSTALL_DIR/.git" ]; then
  ALREADY_INSTALLED=true
  echo "已安裝過了，確認一下所需套件是否齊全..."
else
  echo "正在下載程式..."
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/start.command"

BREW_RUBY_PREFIX="$(brew --prefix ruby 2>/dev/null)"
if [ -z "$BREW_RUBY_PREFIX" ] || [ ! -x "$BREW_RUBY_PREFIX/bin/ruby" ]; then
  echo "正在安裝 Ruby（透過 Homebrew，第一次會花幾分鐘）..."
  brew install ruby
  BREW_RUBY_PREFIX="$(brew --prefix ruby)"
fi

echo "正在安裝所需套件..."
(cd "$INSTALL_DIR" && "$BREW_RUBY_PREFIX/bin/bundle" install)

echo ""
echo "================================"
if [ "$ALREADY_INSTALLED" = true ]; then
  echo "  套件都齊了！"
else
  echo "  安裝完成！"
  echo "  文件夾出現了 rema-keynote-gen 資料夾"
fi
echo "  之後雙擊 start.command 執行"
echo "================================"
echo ""
open "$INSTALL_DIR"
read -p "按 Enter 關閉..."

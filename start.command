#!/bin/bash

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "================================"
echo "  Rema Keynote 產生器"
echo "================================"
echo ""

echo "檢查更新..."
git pull || echo "⚠️  無法更新（請確認網路），使用目前版本繼續。"
echo ""

# 系統內建的 Ruby 版本舊、gem 目錄又是唯讀的，跟 install.command 裝 gem 用的
# Homebrew Ruby 不是同一份，直接用 PATH 上的 `ruby` 可能會撿到系統那個、找不到裝好的 gem。
# 找不到 brew ruby（例如使用者自己手動跑這支腳本、還沒跑過 install.command）就退回系統 ruby，
# 至少 bin/main.rb 本身不依賴任何外部 gem，還跑得動。
BREW_RUBY_PREFIX="$(brew --prefix ruby 2>/dev/null)"
if [ -n "$BREW_RUBY_PREFIX" ] && [ -x "$BREW_RUBY_PREFIX/bin/ruby" ]; then
  RUBY_BIN="$BREW_RUBY_PREFIX/bin/ruby"
else
  RUBY_BIN="ruby"
fi

"$RUBY_BIN" bin/main.rb

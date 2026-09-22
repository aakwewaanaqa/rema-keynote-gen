#!/bin/bash
# 用 tebako 把 ruby 直譯器 + nokogiri 等 gem + src/ + bible_src/ 資料一起壓成單一可執行檔
# rubycli（不依賴使用者機器上裝的 ruby/rbenv/gem）。這支只在「要把 app 包給別人（AirDrop 等）
# 用」的時候才需要跑一次，平常 Swift 端開發／`swift run` 會自動 fallback 用 rbenv 的 ruby，
# 不用每次都重跑一遍（重跑一次通常要幾分鐘）。
#
# 產出：bin/ui/swift_app/rubycli（已加進 .gitignore，不進版控——體積太大且是機器產物）
# package_app.sh 偵測到這支存在就會把它一起塞進 .app/Contents/Resources，讓 app 變成
# 真正不依賴這台機器 ruby 環境的獨立 bundle。
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v tebako >/dev/null 2>&1; then
  echo "找不到 tebako，先跑: gem install tebako" >&2
  exit 1
fi

REPO_ROOT="$(cd ../../.. && pwd)"
BUILD_ROOT="$(pwd)/.tebako_root"

echo "==> 重建打包用的原始碼樹 $BUILD_ROOT"
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT/src" "$BUILD_ROOT/bin/ui/swift_app"

# 保留跟正式 repo 一樣的相對路徑深度（bin/ui/swift_app -> ../../../src/...），
# 這樣 cli 腳本裡的 require_relative 完全不用改
cp -R "$REPO_ROOT/src/." "$BUILD_ROOT/src/"
cp -R "$REPO_ROOT/bible_src/." "$BUILD_ROOT/bible_src/"
cp "$REPO_ROOT/Gemfile" "$REPO_ROOT/Gemfile.lock" "$BUILD_ROOT/"
cp cli_entry.rb advanced_bible_query_cli.rb generate_keynote_cli.rb "$BUILD_ROOT/bin/ui/swift_app/"

# 專案原本的 Gemfile 沒有宣告 source，本機 bundle install 能動是因為系統已經裝過 nokogiri。
# tebako press 用的是全新、乾淨的 gem 環境，沒有 source 的話 bundler 會把自己當成
# 「只能用本機已裝好的 gem」，找不到 nokogiri 就直接失敗——這裡補一行 source 進去。
if ! grep -q '^source ' "$BUILD_ROOT/Gemfile"; then
  printf 'source "https://rubygems.org"\n' | cat - "$BUILD_ROOT/Gemfile" > "$BUILD_ROOT/Gemfile.tmp"
  mv "$BUILD_ROOT/Gemfile.tmp" "$BUILD_ROOT/Gemfile"
fi
if ! grep -q '^  remote:' "$BUILD_ROOT/Gemfile.lock"; then
  sed -i '' '/^GEM$/a\
  remote: https://rubygems.org/
' "$BUILD_ROOT/Gemfile.lock"
fi

echo "==> tebako press（第一次跑會下載/解析 prebuilt runtime，需要網路，可能要幾分鐘）"
tebako press \
  --root="$BUILD_ROOT" \
  --entry=bin/ui/swift_app/cli_entry.rb \
  --output="$(pwd)/rubycli" \
  --mode=fat

echo "==> 完成: $(pwd)/rubycli"
echo "    接著跑 ./package_app.sh 就會把它包進 .app 裡。"

#!/bin/bash
# 把本機聖經資料（bible_src）準備到 App 讀的位置：~/Library/Application Support/RemaKeynoteGen/bible_src
# （見 RemaPaths.bibleSource）。以前放在專案根目錄，有的話直接搬過去，沒有才 clone。
# 失敗不擋 App 啟動，只是本機聖經來源不能用。
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$HOME/Library/Application Support/RemaKeynoteGen/bible_src"

[ -d "$TARGET" ] && exit 0
mkdir -p "$(dirname "$TARGET")"

if [ -d "$DIR/bible_src" ]; then
  echo "搬移本機聖經資料到 $TARGET..."
  mv "$DIR/bible_src" "$TARGET"
else
  echo "下載本機聖經資料..."
  git clone --depth 1 https://github.com/michaelchanwahyan/bible_src.git "$TARGET" \
    || echo "⚠️  本機聖經資料下載失敗（請確認網路），下次啟動會再試。"
fi

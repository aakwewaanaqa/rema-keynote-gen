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

SWIFT_APP_DIR="$DIR/bin/ui/swift_app"
APP_BUNDLE="$SWIFT_APP_DIR/AdvancedBibleQueryApp.app"

# git pull 可能帶來新的程式碼，所以每次都重新打包；SwiftPM 是增量編譯，沒改動時很快。
# package_app.sh 要編譯成功才會動到舊的 .app，所以編譯失敗時舊版還在，可以退回去開舊版。
if ! "$SWIFT_APP_DIR/package_app.sh"; then
  if [ ! -d "$APP_BUNDLE" ]; then
    echo ""
    echo "App 編譯失敗，請把上面的訊息截圖傳給維護的人。"
    echo ""
    read -p "按 Enter 關閉..."
    exit 1
  fi
  echo "⚠️  App 編譯失敗，使用目前版本繼續。"
fi

open "$APP_BUNDLE"

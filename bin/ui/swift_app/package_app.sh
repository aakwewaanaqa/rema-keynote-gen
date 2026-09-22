#!/bin/bash
# 把 SwiftPM 產出的裸執行檔包成正式的 .app bundle（含 Info.plist、bundle identifier）
# 並做 ad-hoc 簽章。ShareLink 的 AirDrop、LINE 等第三方分享擴充只認得
# 「有 bundle identifier、經過簽章」的 App，裸執行檔（swift run / .build 底下的 binary）
# 幾乎不會被系統列進分享清單，這支腳本解決的就是這件事。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="AdvancedBibleQueryApp"
BUILD_CONFIG="release"

echo "==> swift build -c $BUILD_CONFIG"
swift build -c "$BUILD_CONFIG"

BIN_PATH=".build/$BUILD_CONFIG/$APP_NAME"
APP_BUNDLE="$APP_NAME.app"

echo "==> 重建 $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

if [ -x "rubycli" ]; then
  echo "==> 偵測到 rubycli，一併包進 Resources（app 之後不依賴這台機器的 ruby/rbenv 環境）"
  cp rubycli "$APP_BUNDLE/Contents/Resources/rubycli"
else
  echo "==> 沒有 rubycli，app 仍會 fallback 用 ~/.rbenv/shims/ruby（只能在這台機器跑）"
  echo "    要包成能 AirDrop 給別人跑的版本，先跑 ./build_rubycli.sh 再重跑這支腳本"
fi

echo "==> ad-hoc 簽章"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> 向 Launch Services 註冊"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP_BUNDLE"

echo "==> 完成: $APP_BUNDLE"
echo "    以後開這個 App 請直接開 $APP_BUNDLE (例如 open $APP_BUNDLE), 不要再用 swift run。"

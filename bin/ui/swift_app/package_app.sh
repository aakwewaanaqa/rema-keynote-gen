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

# 專案 keynotes/ 底下的範本包進 App，App 啟動時會複製到 ~/Library/Application Support/RemaKeynoteGen/Templates
# （見 RemaPaths.installBundledTemplates）。scratch/ 是實驗品不包。.key 走 Git LFS，沒裝 git-lfs 時拿到的只是文字指標檔，這種不包
echo "==> 打包範本"
mkdir -p "$APP_BUNDLE/Contents/Resources/Templates"
find ../../../keynotes -name "*.key" -not -path "*/scratch/*" -print0 | while IFS= read -r -d "" key; do
  if head -c 40 "$key" | grep -q "git-lfs.github.com"; then
    echo "    略過 $(basename "$key")（Git LFS 指標檔，沒有實際內容）"
  else
    cp -R "$key" "$APP_BUNDLE/Contents/Resources/Templates/"
  fi
done

echo "==> ad-hoc 簽章"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> 向 Launch Services 註冊"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP_BUNDLE"

echo "==> 完成: $APP_BUNDLE"
echo "    以後開這個 App 請直接開 $APP_BUNDLE (例如 open $APP_BUNDLE), 不要再用 swift run。"

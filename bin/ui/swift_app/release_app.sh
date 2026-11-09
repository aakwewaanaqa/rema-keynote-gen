#!/bin/bash
# 做出可以放上 GitHub Release、同工下載後直接雙擊就能開的 App：
# universal（Apple Silicon + Intel）編譯 → Developer ID 簽章（hardened runtime）→ Apple 公證 → staple → zip。
# 跟 package_app.sh 不同：那支是 ad-hoc 簽章、只給這台電腦自己用。
#
# 事前準備（各做一次）：
#   1. Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application
#   2. 到 appleid.apple.com 產生 App 專用密碼，然後在終端機跑（會問密碼，存進鑰匙圈）：
#        xcrun notarytool store-credentials rema-notary --apple-id <Apple ID> --team-id <Team ID>
#
# 用法：./release_app.sh 1.0.0
# 產出：dist/AdvancedBibleQueryApp-1.0.0.zip
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?用法: ./release_app.sh <版本號，例如 1.0.0>}"
APP_NAME="AdvancedBibleQueryApp"
NOTARY_PROFILE="${NOTARY_PROFILE:-rema-notary}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"

if [ -z "$IDENTITY" ]; then
  echo "找不到 Developer ID Application 憑證，請先在 Xcode → Settings → Accounts → Manage Certificates 建立"
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "找不到公證用的鑰匙圈設定「$NOTARY_PROFILE」，請先跑："
  echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <Apple ID> --team-id <Team ID>"
  exit 1
fi

echo "==> universal 編譯（arm64 + x86_64）"
# 會出現「x86_64 is deprecated for your deployment target」警告，那是看這台電腦的系統版本，
# 實際產物的最低版本仍是 Package.swift 的 macOS 13（可用 vtool -show-build 確認）
swift build -c release --arch arm64 --arch x86_64
BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"

DIST="dist"
APP_BUNDLE="$DIST/$APP_NAME.app"
rm -rf "$DIST"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_BUNDLE/Contents/Info.plist"

echo "==> 簽章：$IDENTITY"
codesign --force --options runtime --timestamp --entitlements release.entitlements --sign "$IDENTITY" "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

echo "==> 送 Apple 公證（通常幾分鐘）"
ditto -c -k --keepParent "$APP_BUNDLE" "$DIST/notarize.zip"
xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
rm "$DIST/notarize.zip"

# 把公證結果釘進 App 本身，同工電腦沒網路時 Gatekeeper 也認得
xcrun stapler staple "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE"

# 用 ditto 壓縮才不會弄壞簽章（Finder 的「壓縮」也可以，zip 指令不行）
ZIP="$DIST/$APP_NAME-$VERSION.zip"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP"
echo "==> 完成：$ZIP"

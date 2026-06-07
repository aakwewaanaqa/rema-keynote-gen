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

ruby bin/main.rb

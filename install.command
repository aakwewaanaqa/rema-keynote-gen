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

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "已安裝過了！"
  open "$INSTALL_DIR"
  exit 0
fi

echo "正在下載程式..."
git clone "$REPO_URL" "$INSTALL_DIR"

chmod +x "$INSTALL_DIR/start.command"

echo ""
echo "================================"
echo "  安裝完成！"
echo "  文件夾出現了 rema-keynote-gen 資料夾"
echo "  之後雙擊 start.command 執行"
echo "================================"
echo ""
open "$INSTALL_DIR"
read -p "按 Enter 關閉..."

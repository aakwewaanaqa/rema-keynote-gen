#!/usr/bin/env ruby
# frozen_string_literal: true

# 給 AppKit/SwiftUI 端呼叫的 CLI 包裝：列出 Keynote 範本裡所有母片（slide layout）名稱，
# 讓使用者在產生 Keynote 前挑要套用哪一張母片（對照 generate_keynote_cli.rb 的 master_name 參數）。
# 用法：ruby list_keynote_layouts_cli.rb "<Keynote 範本路徑>"
# 輸出：JSON { layouts?: [...], error?: } 到 stdout

require "json"
require_relative "../../../src/keynote_runner"

# 同 generate_keynote_cli.rb：呼叫端只解析 stdout 的 JSON，錯誤也要走 stdout
def fail_with(message)
  puts JSON.generate({ error: message })
  exit
end

template_path = ARGV[0]&.dup&.force_encoding('UTF-8')

fail_with("缺少 Keynote 範本路徑") if template_path.nil? || template_path.empty?
fail_with("找不到範本檔案: #{template_path}") unless File.exist?(template_path)

result = begin
  KeynoteRunner.layout_names(template_path)
rescue => e
  fail_with("osascript 執行失敗: #{e.message}")
end

fail_with("讀取母片失敗（osascript 回傳失敗，請確認 Keynote 已安裝、範本檔案可開啟）") unless result[:success]

puts JSON.generate({ layouts: result[:names] })

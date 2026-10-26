#!/usr/bin/env ruby
# frozen_string_literal: true

# 給 AppKit/SwiftUI 端呼叫的 CLI 包裝：列出 Keynote 目前開著（且存過檔）的文件，
# 讓使用者產生 Keynote 時可以直接挑開著的檔案當範本，不用再去檔案面板翻一次。
# 用法：ruby list_keynote_open_documents_cli.rb
# 輸出：JSON { documents?: [{ path:, modified: }, ...], error?: } 到 stdout

require "json"
require_relative "../../../src/keynote_runner"

result = begin
  KeynoteRunner.open_documents
rescue => e
  { success: false, message: e.message }
end

# 同 generate_keynote_cli.rb：呼叫端只解析 stdout 的 JSON，錯誤也要走 stdout
unless result[:success]
  puts JSON.generate({ error: "讀取 Keynote 開啟中的檔案失敗#{result[:message] && "：#{result[:message]}"}" })
  exit
end

puts JSON.generate({ documents: result[:documents] })

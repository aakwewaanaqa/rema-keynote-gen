#!/usr/bin/env ruby
# frozen_string_literal: true

# 給 AppKit/SwiftUI 端呼叫的 CLI 包裝：查經文 -> 依 placeholder 範本代換 -> 透過
# KeynoteRunner（osascript）把內容套進 Keynote 範本、輸出投影片。跟 advanced_bible_query_cli.rb
# 分開，因為查詢/預覽跟「真的動 Keynote」是兩個不同時機觸發的動作。
# 用法：ruby generate_keynote_cli.rb "<搜尋經節序號>" "<啟用的來源 token，逗號分隔>" "<Keynote 範本路徑>" "<輸出資料夾>" '<placeholders JSON>'
#   placeholders JSON 格式：[{ "placeholder": "...", "format": "{中}" }, ...]
# 輸出：JSON { status:, output_dir?:, errors?: [...], error?: } 到 stdout

require "json"
require_relative "../../../src/shared/readable_pos"
require_relative "../../../src/shared/string_consumer"
require_relative "../../../src/shared/token"
require_relative "../../../src/shared/token_consumer"
require_relative "../../../src/domain/bible"
require_relative "../../../src/domain/interpret"
require_relative "../../../src/domain/search_dsl/ast"
require_relative "../../../src/domain/search_dsl/tokenize"
require_relative "../../../src/domain/bible_query"
require_relative "../../../src/domain/bible_template"
require_relative "../../../src/service/bible_query_verse"
require_relative "../../../src/service/github_micheal_chan_bible.s"
require_relative "../../../src/service/spring_bible.s"
require_relative "../../../src/service/bible_gateway_service.s"
require_relative "../../../src/service/holy_bible_korean_service.s"
require_relative "../../../src/keynote_runner"

# 不要用 abort/raise 到最上層：那會印到 stderr 或直接跳例外，呼叫端（Process）只解析 stdout 的 JSON，
# 結果就是完全收不到任何輸出、JSON 解析失敗（同樣的坑對照 advanced_bible_query_cli.rb）
def fail_with(message)
  puts JSON.generate({ status: "產生失敗: #{message}", error: message })
  exit
end

# Keynote 匯出的檔名（如 template.001.png）看不出對應哪節經文，這裡把檔名換成查詢資料裡的書卷/章/節。
# entries 跟 slide_groups 是同一個順序（由 outcome[:entries].map 產生），所以「第 N 張投影片」
# 就對應 entries[N-1]；用檔名裡的數字排序而不是字串排序，避免超過 9 張時 "10" 排到 "2" 前面。
def rename_exported_slides(export_dir, entries)
  files = Dir.glob(File.join(export_dir, '*.png')).sort_by { |f| File.basename(f)[/\d+/].to_i }
  return { renamed: [], warning: nil } if files.empty?

  warning = if files.size != entries.size
              "匯出的圖片數量（#{files.size}）跟經節數量（#{entries.size}）對不上，檔名可能對應不準確，已盡量重新命名"
            end

  count = [files.size, entries.size].min
  renamed = (0...count).map do |i|
    entry = entries[i]
    info = Domain::Bible.chapter_info(entry[:book])
    book = (info && info[:chinese]) || entry[:book].to_s
    new_name = format('%02d_%s%s-%s.png', i + 1, book, entry[:chapter], entry[:verse])
    File.rename(files[i], File.join(export_dir, new_name))
    new_name
  end

  { renamed: renamed, warning: warning }
end

raw_text      = ARGV[0]&.dup&.force_encoding('UTF-8')
enabled_text  = ARGV[1]&.dup&.force_encoding('UTF-8') || ''
template_path = ARGV[2]&.dup&.force_encoding('UTF-8')
output_dir    = ARGV[3]&.dup&.force_encoding('UTF-8')
placeholders_json = ARGV[4]&.dup&.force_encoding('UTF-8') || '[]'

fail_with("缺少查詢字串") if raw_text.nil? || raw_text.empty?
fail_with("缺少 Keynote 範本路徑") if template_path.nil? || template_path.empty?
fail_with("找不到範本檔案: #{template_path}") unless template_path && File.exist?(template_path)
fail_with("缺少輸出資料夾") if output_dir.nil? || output_dir.empty?

placeholders = begin
  JSON.parse(placeholders_json)
rescue JSON::ParserError => e
  fail_with("placeholder 格式錯誤: #{e.message}")
end
fail_with("至少需要一個 placeholder") if placeholders.empty?

# token 順序要跟 Domain::BibleTemplate::SOURCE_TOKENS 的 index 對齊
token_sources = [
  ['local', Service::GithubMichaelChanBible],
  ['fhl',   Service::SpringBibleService],
  ['niv',   Service::BibleGatewayService],
  ['gae',   Service::HolyBibleKoreanService],
  ['nkjv',  Service::BibleGatewayServiceNKJV],
  ['kjv',   Service::BibleGatewayServiceKJV],
]

enabled_tokens = enabled_text.split(',').map(&:strip).reject(&:empty?)
sources = token_sources.map { |token, service| [enabled_tokens.include?(token), service] }
fail_with("請至少勾選一個查詢來源（可用: #{token_sources.map(&:first).join('/')}）") if sources.none? { |enabled, _| enabled }

outcome = begin
  Domain::BibleQuery.run(raw_text, sources)
rescue => e
  { error: e.message }
end
fail_with(outcome[:error]) if outcome[:error]
fail_with("查無經文") if outcome[:entries].empty?

errors = outcome[:source_errors].dup
slide_groups = outcome[:entries].map { |entry|
  placeholders.map { |ph| Domain::BibleTemplate.render_placeholder(ph['format'].to_s, entry, errors, ph['placeholder'].to_s) }
}
placeholder_names = placeholders.map { |ph| ph['placeholder'].to_s }

result = begin
  KeynoteRunner.export(
    template: template_path,
    slide_groups: slide_groups,
    placeholders: placeholder_names,
    output_dir: output_dir
  )
rescue => e
  fail_with("osascript 執行失敗: #{e.message}")
end

fail_with("Keynote 產生失敗（osascript 回傳失敗，請確認 Keynote 已安裝、範本檔案可開啟）") unless result[:success]

rename_outcome = rename_exported_slides(result[:export_dir], outcome[:entries])
errors << rename_outcome[:warning] if rename_outcome[:warning]

status = "已產生 #{slide_groups.size} 張投影片"
status += "（#{errors.size} 個警告）" unless errors.empty?

puts JSON.generate({ status: status, output_dir: result[:export_dir], errors: errors })

#!/usr/bin/env ruby
# frozen_string_literal: true

# 給 AppKit 端呼叫的 CLI 包裝，對應 bin/ui/windows/advanced_bible_query_window.rb 的 run_query + render_preview 邏輯。
# 用法：ruby advanced_bible_query_cli.rb "<搜尋經節序號>" "<格式範本文字>"
# 輸出：JSON { status: "...", preview: "..." } 到 stdout（跟 Ruby 視窗版狀態文字/預覽內容一致）

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

raw_text = ARGV[0]&.dup&.force_encoding('UTF-8')
format_text = ARGV[1]&.dup&.force_encoding('UTF-8')

if raw_text.nil? || raw_text.empty? || format_text.nil?
  abort JSON.generate({ error: "缺少查詢字串或格式範本" })
end

# token 順序要跟 Domain::BibleTemplate::SOURCE_TOKENS 的 index 對齊
token_sources = [
  ['local', Service::GithubMichaelChanBible],
  ['fhl',   Service::SpringBibleService],
  ['niv',   Service::BibleGatewayService],
  ['gae',   Service::HolyBibleKoreanService],
]

sections = Domain::BibleTemplate.parse(format_text)

if sections.empty?
  puts JSON.generate({
    status: '格式錯誤：找不到任何 #region 區塊（範例："#sec1 {fhl}"）',
    preview: '',
  })
  exit
end

used_tokens = sections.flat_map { |_, body| body.scan(/\{(\w+)\}/).flatten }.uniq
sources = token_sources.map { |token, service| [used_tokens.include?(token), service] }

if sources.none? { |enabled, _| enabled }
  puts JSON.generate({
    status: "格式裡沒有用到任何經文來源 token（可用: #{token_sources.map(&:first).join('/')}）",
    preview: '',
  })
  exit
end

outcome = begin
  Domain::BibleQuery.run(raw_text, sources)
rescue => e
  { error: e.message }
end

if outcome[:error]
  puts JSON.generate({ status: "查詢失敗: #{outcome[:error]}", preview: '' })
  exit
end

errors = []
blocks = outcome[:entries].flat_map { |entry|
  sections.map { |name, body| Domain::BibleTemplate.render_placeholder(body, entry, errors, name) }
}

preview = blocks.join("\n\n")
status = errors.empty? ? "共 #{outcome[:entries].size} 節，預覽已產生" : "預覽含 #{errors.size} 個錯誤：\n#{errors.join("\n")}"

puts JSON.generate({ status: status, preview: preview })

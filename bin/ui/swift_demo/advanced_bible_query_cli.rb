#!/usr/bin/env ruby
# frozen_string_literal: true

# 給 AppKit 端呼叫的 CLI 包裝，對應 bin/ui/windows/advanced_bible_query_window.rb 的 run_query 邏輯。
# 這裡只負責查經文，直接輸出結構化的節資料給 Swift 端存成 QueriedVerseGroup 陣列——
# #region/{token} 範本代換是「產生 Keynote」那一步的事，跟查詢分開。
# 來源不是自動掃描出來的，是由第二個參數明講要查哪些來源（對應 SwiftUI 那邊的服務勾選框）。
# 用法：ruby advanced_bible_query_cli.rb "<搜尋經節序號>" "<啟用的來源 token，逗號分隔，如 fhl,niv>"
# 輸出：JSON { status: "...", verses: [{ chapter:, verse:, translations: [{ service:, translation:, book:, content: }, ...] }, ...] } 到 stdout
# 同一節經文的不同譯本合併成一個 item（translations 陣列），而不是每個譯本各自一筆——
# Domain::BibleQuery.run 回傳的 entries 本來就是照這樣分組的，這裡直接沿用，不要拆散了又要 Swift 端重組。

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
require_relative "../../../src/service/bible_query_verse"
require_relative "../../../src/service/github_micheal_chan_bible.s"
require_relative "../../../src/service/spring_bible.s"
require_relative "../../../src/service/bible_gateway_service.s"
require_relative "../../../src/service/holy_bible_korean_service.s"

raw_text = ARGV[0]&.dup&.force_encoding('UTF-8')
enabled_text = ARGV[1]&.dup&.force_encoding('UTF-8') || ''

if raw_text.nil? || raw_text.empty?
  # 不要用 abort：那會印到 stderr，但呼叫端（AppKit/Swift Process）只接了 stdout，
  # 結果就是完全收不到任何輸出、JSON 解析失敗
  puts JSON.generate({ error: "缺少查詢字串" })
  exit
end

# token 順序要跟 Domain::BibleTemplate::SOURCE_TOKENS 的 index 對齊
token_sources = [
  ['local', Service::GithubMichaelChanBible],
  ['fhl',   Service::SpringBibleService],
  ['niv',   Service::BibleGatewayService],
  ['gae',   Service::HolyBibleKoreanService],
  ['nkjv',  Service::BibleGatewayServiceNKJV],
]

translations = {
  'local' => '麥可陳',
  'fhl'   => '信望愛 CUV',
  'niv'   => 'NIV',
  'gae'   => '개역개정',
  'nkjv'  => 'NKJV',
}

# 書卷名要跟著該譯本的語言變，不是每個譯本都硬塞中文書名
book_name_keys = {
  'local' => :chinese,
  'fhl'   => :chinese,
  'niv'   => :english,
  'gae'   => :korean,
  'nkjv'  => :english,
}

enabled_tokens = enabled_text.split(',').map(&:strip).reject(&:empty?)
sources = token_sources.map { |token, service| [enabled_tokens.include?(token), service] }

if sources.none? { |enabled, _| enabled }
  puts JSON.generate({
    status: "請至少勾選一個查詢來源（可用: #{token_sources.map(&:first).join('/')}）",
    verses: [],
  })
  exit
end

outcome = begin
  Domain::BibleQuery.run(raw_text, sources)
rescue => e
  { error: e.message }
end

if outcome[:error]
  puts JSON.generate({ status: "查詢失敗: #{outcome[:error]}", verses: [] })
  exit
end

verses = outcome[:entries].map { |e|
  info = Domain::Bible.chapter_info(e[:book])

  # 不用 filter_map：Swift App 啟動時繼承的 PATH 沒有終端機的 rbenv shim，
  # `/usr/bin/env ruby` 常常會落到系統內建的舊版 Ruby，filter_map 是 2.7 才有的方法
  verse_translations = e[:texts].each_with_index.map { |text, idx|
    next nil if text.nil? || text.empty?

    token = token_sources[idx][0]
    book_name_key = book_name_keys[token] || :chinese
    book_name = (info && info[book_name_key]) || e[:book].to_s
    {
      service: token,
      translation: translations[token] || token,
      book: book_name,
      content: text,
    }
  }.compact

  next nil if verse_translations.empty?

  {
    chapter: e[:chapter],
    verse: e[:verse],
    translations: verse_translations,
  }
}.compact

status = "共 #{outcome[:entries].size} 節，已取得經文"

puts JSON.generate({ status: status, verses: verses })

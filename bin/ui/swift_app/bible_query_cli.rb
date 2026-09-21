#!/usr/bin/env ruby
# frozen_string_literal: true

# 評估用：給 SwiftUI 端呼叫的小 CLI 包裝。
# 用法：ruby bible_query_cli.rb "太18:18-20"
# 輸出：JSON { rows: [[標籤, 經文], ...] } 到 stdout

require "json"
require_relative "../../../src/shared/readable_pos"
require_relative "../../../src/shared/string_consumer"
require_relative "../../../src/shared/token"
require_relative "../../../src/shared/token_consumer"
require_relative "../../../src/domain/bible"
require_relative "../../../src/domain/search_dsl/ast"
require_relative "../../../src/domain/search_dsl/tokenize"
require_relative "../../../src/domain/bible_query"
require_relative "../../../src/service/spring_bible.s"

raw_text = ARGV[0]
abort JSON.generate({ error: "缺少查詢字串" }) if raw_text.nil? || raw_text.empty?

outcome = begin
  Domain::BibleQuery.run(raw_text, [[true, Service::SpringBibleService]])
rescue => e
  { error: e.message }
end

if outcome[:error]
  puts JSON.generate({ error: outcome[:error] })
else
  puts JSON.generate({ rows: outcome[:rows] })
end

#!/usr/bin/env ruby
# frozen_string_literal: true

# Tebako 打包後單一可執行檔（rubycli）的進入點。
# advanced_bible_query_cli.rb / generate_keynote_cli.rb 兩支腳本共用同一份打包好的
# ruby + gem（nokogiri 等），不必各自壓一份 tebako image——那樣 app 體積會直接乘二。
# 用法：rubycli query    <...advanced_bible_query_cli.rb 原本的參數>
#      rubycli generate <...generate_keynote_cli.rb 原本的參數>
command = ARGV.shift
script = case command
         when "query" then "advanced_bible_query_cli.rb"
         when "generate" then "generate_keynote_cli.rb"
         end

unless script
  require "json"
  # 不用 abort：呼叫端（Swift Process）只接 stdout，abort 印到 stderr 會讓 JSON 解析直接失敗
  puts JSON.generate({ error: "未知的 rubycli 指令: #{command.inspect}" })
  exit
end

load File.join(__dir__, script)

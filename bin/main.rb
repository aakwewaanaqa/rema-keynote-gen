#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require_relative '../src/lyrics_parser'
require_relative '../src/keynote_runner'

def choose_file(prompt)
  result = `osascript -e 'POSIX path of (choose file with prompt "#{prompt}")'`.chomp
  exit if result.empty?
  result
end

# KeynoteRunner.export 把圖片匯出到 output_dir 底下另一個暫存的 keynote_export_TIMESTAMP
# 子資料夾（避開 Keynote「目的資料夾已存在就匯出失敗」的限制），檔名也是照那個暫存資料夾
# 命名，例如 keynote_export_20260912_120000.001.png——這裡把檔案搬回 output_dir，
# 依段落名稱＋順序重新命名（如 V1.001.png），搬完把已經空了的暫存資料夾刪掉
def move_exported_slides(export_dir, output_dir, section_name)
  files = Dir.glob(File.join(export_dir, "*.png")).sort_by { |f| File.basename(f)[/\d+/].to_i }
  files.each_with_index do |f, i|
    new_name = format("%s.%03d.png", section_name, i + 1)
    FileUtils.mv(f, File.join(output_dir, new_name))
  end
  Dir.rmdir(export_dir)
end

def choose_folder(prompt)
  result = `osascript -e 'POSIX path of (choose folder with prompt "#{prompt}")'`.chomp
  exit if result.empty?
  result.chomp("/")
end

template   = choose_file("選擇模板 .key 檔案")
lyrics_dir = choose_folder("選擇歌詞資料夾")

lyrics_files = Dir.glob(File.join(lyrics_dir, "*.txt")).sort
abort "資料夾內沒有 .txt 歌詞檔" if lyrics_files.empty?

puts "\n找到 #{lyrics_files.size} 個歌詞檔\n"

lyrics_files.each do |lyrics_file|
  song_name  = File.basename(lyrics_file, ".txt")
  song_dir   = File.join(lyrics_dir, song_name)
  puts "\n▶ #{song_name}"

  result = LyricsParser.parse(lyrics_file)

  result.sections.each do |section_name, slide_groups|
    output_dir = File.join(song_dir, section_name)
    print "  #{section_name} (#{slide_groups.size} 張)... "
    $stdout.flush

    outcome = KeynoteRunner.export(
      template:     template,
      slide_groups: slide_groups,
      placeholders: result.placeholders,
      output_dir:   output_dir
    )

    if outcome[:success]
      move_exported_slides(outcome[:export_dir], output_dir, section_name)
      puts "完成"
    else
      puts "失敗"
    end
  end
end

puts "\n全部完成"

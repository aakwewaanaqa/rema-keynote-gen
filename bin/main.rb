#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../src/lyrics_parser'
require_relative '../src/keynote_runner'

def choose_file(prompt)
  result = `osascript -e 'POSIX path of (choose file with prompt "#{prompt}")'`.chomp
  exit if result.empty?
  result
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

    success = KeynoteRunner.export(
      template:     template,
      slide_groups: slide_groups,
      placeholders: result.placeholders,
      output_dir:   output_dir
    )

    puts success ? "完成" : "失敗"
  end
end

puts "\n全部完成"

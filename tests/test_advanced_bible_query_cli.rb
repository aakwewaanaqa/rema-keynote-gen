require 'minitest/autorun'
require 'json'
require 'open3'

# 這支測試不是測 Ruby 的 domain 邏輯（那些已經有 test_seach_dsl.rb 之類的覆蓋），
# 是專門守住 bin/ui/swift_demo/advanced_bible_query_cli.rb 對 Swift 端的 JSON 契約：
# Swift 的 Process 只接 stdout，任何一行意外印到 stderr、或用了呼叫端 ruby 版本不支援的語法，
# 對 Swift 來說都是同一種症狀——「無法解析輸出」，很難從 Swift 那邊的 log 反查回來。
# 用 Open3 實際跑一次 CLI（跟 Swift 端 Process 呼叫方式一樣），斷言 stdout 永遠是合法 JSON。
class TestAdvancedBibleQueryCli < Minitest::Test
  CLI_PATH = File.expand_path('../bin/ui/swift_demo/advanced_bible_query_cli.rb', __dir__)

  def run_cli(*args)
    stdout, stderr, status = Open3.capture3('ruby', CLI_PATH, *args)
    [stdout, stderr, status]
  end

  def parsed_stdout(*args)
    stdout, stderr, _status = run_cli(*args)
    JSON.parse(stdout)
  rescue JSON::ParserError => e
    flunk "stdout 不是合法 JSON（stderr: #{stderr.inspect}）：#{e.message}\nstdout: #{stdout.inspect}"
  end

  # 對照之前 `abort` 印到 stderr、Swift 端完全收不到輸出的那個 bug
  def test_empty_search_text_still_outputs_json_to_stdout
    parsed = parsed_stdout('', 'local')
    assert parsed.key?('error')
  end

  def test_no_source_enabled_outputs_json_to_stdout
    parsed = parsed_stdout('創1:1', '')
    assert_equal [], parsed['verses']
    refute_nil parsed['status']
  end

  def test_local_source_returns_structured_verses
    parsed = parsed_stdout('創1:1', 'local')
    assert_nil parsed['error']

    verses = parsed['verses']
    assert_equal 1, verses.length
    verse = verses[0]
    assert_equal 'local', verse['service']
    assert_equal '創世記', verse['book']
    assert_equal 1, verse['chapter']
    assert_equal 1, verse['verse']
    assert_equal '起初，神創造天地。', verse['content']
  end

  def test_verse_range_returns_multiple_entries
    parsed = parsed_stdout('創1:1-3', 'local')
    assert_equal 3, parsed['verses'].length
    assert_equal [1, 2, 3], parsed['verses'].map { |v| v['verse'] }
  end

  # 對照之前 filter_map（Ruby 2.7+ 才有）在系統內建舊版 Ruby 上炸掉的那個 bug：
  # Swift App 啟動時繼承的 PATH 常常找不到開發機終端機用的新版 Ruby（如 rbenv shim），
  # `/usr/bin/env ruby` 落到系統版是常態，所以這裡特地用系統版 Ruby 再跑一次同樣的斷言
  def test_works_under_system_ruby
    system_ruby = '/usr/bin/ruby'
    skip "找不到系統 ruby (#{system_ruby})，略過" unless File.executable?(system_ruby)

    stdout, stderr, _status = Open3.capture3(system_ruby, CLI_PATH, '創1:1', 'local')
    parsed = begin
      JSON.parse(stdout)
    rescue JSON::ParserError => e
      flunk "系統 ruby 執行失敗，stdout 不是合法 JSON（stderr: #{stderr.inspect}）：#{e.message}"
    end

    assert_nil parsed['error']
    assert_equal 1, parsed['verses'].length
  end
end

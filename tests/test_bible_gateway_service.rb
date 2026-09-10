require 'minitest/autorun'
require_relative '../src/src.rb'
require_relative '../src/service/bible_gateway_service.s.rb'

Ast = ::Domain::SearchDsl::Ast unless defined?(Ast)

# 打真的 biblegateway.com，跟 tests/test_seach_dsl.rb 裡 TestGithubMichaelChanBibleQuery 一樣是網路測試。
# 這支主要是要守住 BibleGatewayServiceNKJV：它是共用 BibleGatewayService 的爬蟲、只是換一個 version 參數，
# 如果哪天 biblegateway.com 的 DOM 結構又變了（之前 div.std-text 已經被換成 div.passage-text 炸過一次），
# NIV 跟 NKJV 兩條路徑會一起壞掉，所以兩個都測。
class TestBibleGatewayServiceQuery < Minitest::Test
  def query(cls, str)
    cls.query(Ast.parse(str))
  end

  def test_niv_single_verse
    results = query(Service::BibleGatewayService, 'Gen1:1')
    assert_equal 1, results.length
    verse = results[0]
    assert_equal :Genesis, verse.book
    assert_equal 1, verse.chapter
    assert_equal 1, verse.verse
    assert_match(/beginning/i, verse.text)
  end

  def test_nkjv_single_verse
    results = query(Service::BibleGatewayServiceNKJV, 'Gen1:1')
    assert_equal 1, results.length
    verse = results[0]
    assert_equal :Genesis, verse.book
    assert_equal 1, verse.chapter
    assert_equal 1, verse.verse
    assert_match(/beginning/i, verse.text)
  end

  # 挑一節 NIV/NKJV 譯文明顯不同的經文，確認 version 參數真的有生效，
  # 不是兩邊悄悄查到同一份內容
  def test_nkjv_and_niv_return_different_translations
    niv = query(Service::BibleGatewayService, 'Ps23:1').first.text
    nkjv = query(Service::BibleGatewayServiceNKJV, 'Ps23:1').first.text

    assert_match(/lack nothing/i, niv)
    assert_match(/shall not want/i, nkjv)
    refute_equal niv, nkjv
  end

  def test_nkjv_verse_range
    results = query(Service::BibleGatewayServiceNKJV, 'Gen1:1-3')
    assert_equal 3, results.length
    assert_equal [1, 2, 3], results.map(&:verse)
    assert results.all? { |v| v.book == :Genesis && v.chapter == 1 }
  end
end

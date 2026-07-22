require 'minitest/autorun'
require 'pp'
require_relative '../src/src.rb'
require_relative '../src/service/github_micheal_chan_bible.s.rb'

Ast = ::Domain::SearchDsl::Ast

class TestSearchDslTokenize < Minitest::Test
  def test_DO_IDENTIFIER
    sc = ::Shared::StringConsumer.new '馬太福音'
    tokens = ::Domain::SearchDsl::Tokenize::TOKENIZE.(sc)
    assert_equal(tokens.length, 1)
    assert_equal(tokens[0].last, :identifier)
  end

  def test_token_types
    sc = ::Shared::StringConsumer.new '馬太福音3:4,5～7；彼得前書1:7'
    tokens = ::Domain::SearchDsl::Tokenize::TOKENIZE.(sc)
    assert_equal(tokens.length, 13)
    assert_equal(tokens.map(&:last), [
      :identifier,
      :number,
      :colon,
      :number,
      :comma,
      :number,
      :hyphen,
      :number,
      :semicolon,
      :identifier,
      :number,
      :colon,
      :number
    ])
  end
end

class TestSearchDslAst < Minitest::Test
  def parse(str)
    Ast.parse(str)
  end

  def test_whole_chapter
    q = parse('創1')
    assert_equal 1, q.refs.length
    ref = q.refs[0]
    assert_equal :Genesis, ref.book
    assert_equal 1, ref.chapter
    assert_nil ref.verses
  end

  def test_single_verse
    q = parse('創1:1')
    ref = q.refs[0]
    assert_equal :Genesis, ref.book
    assert_equal 1, ref.chapter
    assert_equal [Ast::Single.new(1)], ref.verses
  end

  def test_verse_range
    q = parse('創1:1-5')
    ref = q.refs[0]
    assert_equal [Ast::VRange.new(1, 5)], ref.verses
  end

  def test_mixed_verse_list
    q = parse('太1:1-5,7,8,10-12')
    ref = q.refs[0]
    assert_equal :Matthew, ref.book
    assert_equal 1, ref.chapter
    assert_equal [
      Ast::VRange.new(1, 5),
      Ast::Single.new(7),
      Ast::Single.new(8),
      Ast::VRange.new(10, 12)
    ], ref.verses
  end

  def test_multiple_refs_with_semicolon
    q = parse('太1:1-5,7,8,10-12;創3:7')
    assert_equal 2, q.refs.length

    assert_equal :Matthew, q.refs[0].book
    assert_equal 1, q.refs[0].chapter
    assert_equal [
      Ast::VRange.new(1, 5),
      Ast::Single.new(7),
      Ast::Single.new(8),
      Ast::VRange.new(10, 12)
    ], q.refs[0].verses

    assert_equal :Genesis, q.refs[1].book
    assert_equal 3, q.refs[1].chapter
    assert_equal [Ast::Single.new(7)], q.refs[1].verses
  end

  def test_chinese_full_name
    q = parse('馬太福音3:4,5～7；彼得前書1:7')
    assert_equal 2, q.refs.length
    assert_equal :Matthew, q.refs[0].book
    assert_equal 3, q.refs[0].chapter
    assert_equal [Ast::Single.new(4), Ast::VRange.new(5, 7)], q.refs[0].verses
    assert_equal :'1Peter', q.refs[1].book
    assert_equal 1, q.refs[1].chapter
    assert_equal [Ast::Single.new(7)], q.refs[1].verses
  end

  def test_english_acronym
    q = parse('Matt3:16')
    ref = q.refs[0]
    assert_equal :Matthew, ref.book
    assert_equal 3, ref.chapter
    assert_equal [Ast::Single.new(16)], ref.verses
  end

  def test_unknown_book_returns_empty
    q = parse('不存在書9:1')
    assert_equal 0, q.refs.length
  end
end

class TestGithubMichaelChanBibleQuery < Minitest::Test
  Bible = Service::GithubMichaelChanBible

  def query(str, **opts)
    Bible.query(Ast.parse(str), **opts)
  end

  def test_single_verse
    results = query('創1:1')
    assert_equal 1, results.length
    assert_equal({ chapter: 1, verse: 1, text: '起初，神創造天地。' }, results[0].to_h)
  end

  def test_verse_range
    results = query('創1:1-3')
    assert_equal 3, results.length
    assert_equal [1, 2, 3], results.map { |r| r[:verse] }
  end

  def test_mixed_verse_list
    results = query('太5:3,5')
    assert_equal 2, results.length
    assert_equal [3, 5], results.map { |r| r[:verse] }
  end

  def test_whole_chapter
    results = query('約3')
    assert results.length > 1
    assert results.all? { |r| r[:chapter] == 3 }
  end

  def test_multiple_books
    results = query('太5:3;約3:16')
    assert_equal 2, results.length
    assert_equal 5,  results[0][:chapter]
    assert_equal 3,  results[0][:verse]
    assert_equal 3,  results[1][:chapter]
    assert_equal 16, results[1][:verse]
  end

  def test_unknown_book_returns_empty
    results = query('不存在書9:1')
    assert_equal [], results
  end

  def test_translation_kjv
    results = query('Gen1:1', translation: 'kjv')
    assert_equal 1, results.length
    assert_match(/beginning/i, results[0][:text])
  end
end

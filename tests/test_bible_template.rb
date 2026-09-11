require 'minitest/autorun'
require_relative '../src/domain/bible'
require_relative '../src/domain/bible_template'

class TestBibleTemplate < Minitest::Test
  def entry
    {
      book: :Acts,
      chapter: 6,
      verse: 1,
      texts: ['麥可陳內容', '信望愛內容', 'NIV content', 'gae content', 'NKJV content', 'KJV content'],
    }
  end

  def test_alias_tokens_resolve_to_same_value_as_canonical_token
    errors = []
    rendered = Domain::BibleTemplate.render_placeholder('{中} / {cuv}', entry, errors, 'p')
    assert_equal '信望愛內容 / 信望愛內容', rendered
    assert_empty errors
  end

  def test_computed_token_aliases
    errors = []
    rendered = Domain::BibleTemplate.render_placeholder(
      '{中書}/{cb} {英書}/{eb} {韓書}/{kb} {章}/{ch} {節}/{vr}', entry, errors, 'p'
    )
    assert_equal '使徒行傳/使徒行傳 Acts/Acts 사도행전/사도행전 6/6 1/1', rendered
    assert_empty errors
  end

  def test_kjv_source_token
    errors = []
    rendered = Domain::BibleTemplate.render_placeholder('{kjv}', entry, errors, 'p')
    assert_equal 'KJV content', rendered
    assert_empty errors
  end

  def test_source_alias_tokens
    errors = []
    rendered = Domain::BibleTemplate.render_placeholder('{英} {韓} {英王} {新英王}', entry, errors, 'p')
    assert_equal 'NIV content gae content KJV content NKJV content', rendered
    assert_empty errors
  end

  def test_chinese_token_names_are_matched_even_though_not_ascii_word_chars
    # \w 預設不吃中文字，這裡確認 render_placeholder 用的擷取規則有處理到這件事
    errors = []
    rendered = Domain::BibleTemplate.render_placeholder('{章}', entry, errors, 'p')
    assert_equal '6', rendered
    assert_empty errors
  end

  def test_unknown_token_reports_original_alias_text_not_canonical
    errors = []
    rendered = Domain::BibleTemplate.render_placeholder('{不存在}', entry, errors, 'p')
    assert_equal '⚠️{不存在}', rendered
    assert_equal 1, errors.length
    assert_match(/未知的 token \{不存在\}/, errors.first)
  end

  def test_canonical_token_passes_through_unknown_names
    assert_equal 'niv', Domain::BibleTemplate.canonical_token('niv')
    assert_equal 'fhl', Domain::BibleTemplate.canonical_token('中')
    assert_equal 'niv', Domain::BibleTemplate.canonical_token('英')
    assert_equal 'kjv', Domain::BibleTemplate.canonical_token('英王')
    assert_equal 'nkjv', Domain::BibleTemplate.canonical_token('新英王')
    assert_equal 'not_a_token', Domain::BibleTemplate.canonical_token('not_a_token')
  end
end

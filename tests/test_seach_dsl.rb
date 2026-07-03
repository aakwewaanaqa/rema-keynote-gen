require 'minitest/autorun'
require 'pp'
require_relative '../src/src.rb'

class TestSearchDsl < Minitest::Test
  def test_DO_IDENTIFIER
    sc = ::Shared::StringConsumer.new '馬太福音'
    tokens = ::Domain::SearchDsl::Tokenize::TOKENIZE.(sc)
    assert_equal(tokens.length, 1)
    assert_equal(tokens[0].last, :identifier)
  end

  def test_
    sc = ::Shared::StringConsumer.new '馬太福音3:4,5-7'
    tokens = ::Domain::SearchDsl::Tokenize::TOKENIZE.(sc)
    assert_equal(tokens.length, 8)
    assert_equal(tokens.map(&:last), [
      :identifier,
      :number,
      :colon,
      :number,
      :comma,
      :number,
      :hyphen,
      :number,
    ])
  end
end
require 'uri'
require 'net/http'
require 'nokogiri'
require_relative '../domain/bible'
require_relative '../domain/interpret'
require_relative '../domain/search_dsl/ast'
require_relative 'bible_query_verse'

module Service
  class SpringBibleService
    # 輸入 Query AST，回傳 [BibleQueryVerse, ...]，經文來自 springbible.fhl.net（和合本）
    def self.query(query_ast)
      query_ast.refs.flat_map do |ref|
        pure_index = ::Domain::Interpret.pure_index(ref.book, ref.chapter)
        verses = fetch_a_chapter(pure_index, ref.book, ref.chapter)

        verses.select { |v| ref.verses.nil? || ::Domain::SearchDsl::Ast.verse_in_list?(v.verse, ref.verses) }
      end
    end

    def self.fetch_a_chapter(pure_index, book, chapter)
      uri = URI('https://springbible.fhl.net/Bible2/cgic201/read201.cgi')
      uri.query = URI.encode_www_form(
        na: 0,
        chap: pure_index,
        ver: 'big5',
        ft: 0,
        temp: -1,
        tight: 1
      )

      response = Net::HTTP.get_response(uri)
      # old bible from fhl is encoded in big5
      html = response.body.force_encoding('Big5').encode('UTF-8')
      doc = Nokogiri::HTML(html)

      doc.css('body div ol li').each_with_index.map do |el, i|
        ::Service::BibleQueryVerse.new(book, chapter, i + 1, el.text.strip)
      end
    end
  end
end

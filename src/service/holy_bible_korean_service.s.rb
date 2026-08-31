require 'uri'
require 'net/http'
require 'nokogiri'
require_relative '../domain/bible'
require_relative '../domain/search_dsl/ast'
require_relative 'bible_query_verse'

module Service
  class HolyBibleKoreanService
    # 輸入 Query AST，回傳 [BibleQueryVerse, ...]，經文來自 holybible.or.kr（개역개정 韓文改譯版）
    def self.query(query_ast)
      query_ast.refs.flat_map do |ref|
        verses = fetch_a_chapter(ref.book, ref.chapter)
        verses.select { |v| ref.verses.nil? || ::Domain::SearchDsl::Ast.verse_in_list?(v.verse, ref.verses) }
      end
    end

    def self.fetch_a_chapter(book_code, chapter)
      # VL 是 1-based 書卷序號，創世記到啟示錄順序跟 CHAPTERS 一致
      vl = ::Domain::Bible::CHAPTERS.index { |c| c[:code] == book_code } + 1

      uri = URI('http://www.holybible.or.kr/mobile/B_GAE/cgi/bibleftxt.php')
      uri.query = URI.encode_www_form(VR: 'GAE', VL: vl, CN: chapter, CV: 99)

      response = Net::HTTP.get_response(uri)
      html = response.body.force_encoding('EUC-KR').encode('UTF-8')
      doc = Nokogiri::HTML(html)

      # 每段經文包在 <ol start="NNN" id="b_NNN"> 裡，節號沒有另外標示，
      # 是用 ol 的 start 屬性加上 li 在裡面的順序推算出來的
      doc.css('ol[id^="b_"]').flat_map do |ol|
        start = ol['start'].to_i
        ol.css('li').each_with_index.map do |li, i|
          ::Service::BibleQueryVerse.new(nil, start + i, li.text.strip)
        end
      end
    end
  end
end

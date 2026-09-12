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
      ols = doc.css('ol[id^="b_"]')

      # holybible.or.kr 最近常常自己內部 include 經文用的 bibl_ftxt.php 失敗
      # （回應裡會夾雜 "Connection refused"），外層頁面照樣回 200，
      # 但完全沒有 <ol id="b_..."> 經文區塊——這種情況不要默默回傳空陣列，
      # 不然呼叫端只會覺得「這節沒有韓文翻譯」，看不出是原站掛了
      raise "holybible.or.kr 韓文來源目前無法取得經文（原站可能故障）" if ols.empty?

      ols.flat_map do |ol|
        start = ol['start'].to_i
        ol.css('li').each_with_index.map do |li, i|
          ::Service::BibleQueryVerse.new(book_code, chapter, start + i, li.text.strip)
        end
      end
    end
  end
end

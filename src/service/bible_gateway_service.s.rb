require 'uri'
require 'net/http'
require 'nokogiri'
require_relative '../domain/search_dsl/ast'
require_relative 'bible_query_verse'

module Service
  class BibleGatewayService
    BOOK_ACRONYMS = {
      Genesis: 'Gen', Exodus: 'Exod', Leviticus: 'Lev', Numbers: 'Num', Deuteronomy: 'Deut',
      Joshua: 'Josh', Judges: 'Judg', Ruth: 'Ruth', "1Samuel": '1Sam', "2Samuel": '2Sam',
      "1Kings": '1Kgs', "2Kings": '2Kgs', "1Chronicles": '1Chron', "2Chronicles": '2Chron',
      Ezra: 'Ezra', Nehemiah: 'Neh', Esther: 'Est', Job: 'Job', Psalm: 'Ps', Proverbs: 'Prov',
      Ecclesiastes: 'Eccl', SongOfSongs: 'Song', Isaiah: 'Isa', Jeremiah: 'Jer',
      Lamentations: 'Lam', Ezekiel: 'Ezek', Daniel: 'Dan', Hosea: 'Hos', Joel: 'Joel',
      Amos: 'Amos', Obadiah: 'Obad', Jonah: 'Jonah', Micah: 'Mic', Nahum: 'Nah',
      Habakkuk: 'Hab', Zephaniah: 'Zeph', Haggai: 'Hag', Zechariah: 'Zech', Malachi: 'Mal',
      Matthew: 'Matt', Mark: 'Mark', Luke: 'Luke', John: 'John', Acts: 'Acts', Romans: 'Rom',
      "1Corinthians": '1Cor', "2Corinthians": '2Cor', Galatians: 'Gal', Ephesians: 'Eph',
      Philippians: 'Phil', Colossians: 'Col', "1Thessalonians": '1Thess', "2Thessalonians": '2Thess',
      "1Timothy": '1Tim', "2Timothy": '2Tim', Titus: 'Titus', Philemon: 'Philem', Hebrews: 'Heb',
      James: 'James', "1Peter": '1Pet', "2Peter": '2Pet', "1John": '1John', "2John": '2John',
      "3John": '3John', Jude: 'Jude', Revelation: 'Rev'
    }.freeze

    # 輸入 Query AST，回傳 [BibleQueryVerse, ...]，經文來自 biblegateway.com（NIV）
    def self.query(query_ast)
      query_ast.refs.flat_map do |ref|
        verses = fetch_a_chapter(ref.book, ref.chapter)
        verses.select { |v| ref.verses.nil? || ::Domain::SearchDsl::Ast.verse_in_list?(v.verse, ref.verses) }
      end
    end

    def self.fetch_a_chapter(book_code, chapter)
      acronym = BOOK_ACRONYMS[book_code]
      raise "Unknown book: #{book_code}" unless acronym

      uri = URI('https://www.biblegateway.com/passage/')
      uri.query = URI.encode_www_form(search: "#{acronym}#{chapter}", version: 'NIV')

      response = Net::HTTP.get_response(uri)
      html = response.body.force_encoding('UTF-8')
      doc = Nokogiri::HTML(html)

      container = doc.at_css('div.std-text')
      raise 'BibleGateway page structure changed' unless container

      container.css('h3, sup.crossreference, sup.footnote, sup.versenum, span.chapternum').each(&:remove)

      # 按照 verse class（如 "Matt-18-18"）分組，詩篇這類分行排版一節會有多個 span
      verse_map = {}
      container.css('span.text').each do |el|
        classes = el['class'] || ''
        match = classes.match(/\w+-\d+-(\d+)/)
        next unless match

        verse_num = match[1].to_i
        text = el.text.strip
        next if text.empty?

        (verse_map[verse_num] ||= []) << text
      end

      verse_map.sort.map do |verse_num, parts|
        ::Service::BibleQueryVerse.new(nil, verse_num, parts.join(' '))
      end
    end
  end
end

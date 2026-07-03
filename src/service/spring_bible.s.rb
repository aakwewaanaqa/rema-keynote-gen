require 'uri'
require 'net/http'
require 'nokogiri'

module Service
  class SpringBibleService
    def fetch_a_chapter(singular_index)
      chapter_code = singular_index.chapter_code
      offset = singular_index.chapter_offset
      pure_index = ::Domain::Interpret.pure_index(chapter_code, offset)

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
        Verse.new(
          index: i + 1,
          text: el.text.strip,
          lang: 'zh-TW',
          version: 'CUV',
          book: singular_index.book,
          chapter: singular_index.chapter
        )
      end
    end
  end
end
require 'uri'
require 'net/http'
require 'socket'
require 'nokogiri'
require_relative '../domain/bible'
require_relative '../domain/interpret'
require_relative '../domain/search_dsl/ast'
require_relative 'bible_query_verse'

module Service
  class SpringBibleService
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    MAX_ATTEMPTS = 3
    RETRY_DELAY = 1 # seconds, doubles after each failed attempt

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

      response = get_with_retry(uri)
      # old bible from fhl is encoded in big5
      html = response.body.force_encoding('Big5').encode('UTF-8')
      doc = Nokogiri::HTML(html)

      doc.css('body div ol li').each_with_index.map do |el, i|
        ::Service::BibleQueryVerse.new(book, chapter, i + 1, el.text.strip)
      end
    end

    # springbible.fhl.net 同時有 A/AAAA 記錄，某些網路環境下 IPv6 路由不通但仍會被
    # Net::HTTP 優先嘗試，導致整個 open_timeout 都耗在打不通的 IPv6 上。這裡故意
    # 只解析 IPv4 位址再連線，跳過這個坑（biblegateway.com 只有 A 記錄所以不受影響）。
    def self.resolve_ipv4(host)
      Addrinfo.getaddrinfo(host, nil, Socket::AF_INET, Socket::SOCK_STREAM).first&.ip_address
    rescue SocketError
      nil
    end

    def self.get_with_retry(uri)
      ipv4 = resolve_ipv4(uri.host)

      attempt = 0
      begin
        attempt += 1
        http = Net::HTTP.new(uri.host, uri.port, nil)
        # ipaddr= 是 Ruby 2.7+ 才有的方法，萬一又落到某個沒有 rbenv shims 的舊系統 ruby，
        # 至少不要整個爆掉，退回成不強制 IPv4 的行為
        http.ipaddr = ipv4 if ipv4 && http.respond_to?(:ipaddr=)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http.start { |h| h.get(uri) }
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, Errno::ECONNRESET, SocketError => e
        warn "[SpringBibleService] attempt #{attempt}/#{MAX_ATTEMPTS} failed for #{uri} (ipv4=#{ipv4.inspect}): #{e.class}: #{e.message}"
        raise e if attempt >= MAX_ATTEMPTS

        sleep(RETRY_DELAY * attempt)
        retry
      end
    end
  end
end

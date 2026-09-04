module Domain
  module BibleQuery
    # 依 sources 指定要查的來源查詢經文。回傳：
    #   rows:    表格用的 [[標籤, 經文], ...]（標籤只在該節第一列顯示）
    #   entries: 依 書卷/章/節 分組、排序好的 [{ book:, chapter:, verse:, texts: [...] }, ...]，
    #            texts 陣列順序跟傳入的 sources 一致，格式範本代換要用這份資料
    # sources 是 [[要不要查(Boolean), service], ...]
    def self.run(raw_text, sources)
      ast = Domain::SearchDsl::Ast.parse raw_text
      # 同一節經文，各語言來源合併成同一筆，而不是各自分開列出；
      # key 用 [book, chapter, verse] 而不是只用 verse，避免查詢橫跨多卷書時節號互相覆蓋
      grouped = Hash.new { |h, k| h[k] = Array.new(sources.size, '') }

      sources.each_with_index do |(enabled, service), idx|
        next unless enabled

        service.query(ast).each do |v|
          grouped[[v.book, v.chapter, v.verse]][idx] = v.text
        end
      end

      book_order = Domain::Bible::CHAPTERS.each_with_index.to_h { |c, i| [c[:code], i] }

      entries = grouped.map { |(book, chapter, verse), texts|
        { book: book, chapter: chapter, verse: verse, texts: texts }
      }.sort_by { |e| [book_order[e[:book]] || 0, e[:chapter].to_i, e[:verse]] }

      rows = entries.flat_map { |e|
        info = Domain::Bible.chapter_info(e[:book])
        label = "#{info && info[:chinese]}#{e[:chapter]}:#{e[:verse]}"
        non_empty = e[:texts].reject(&:empty?)
        non_empty.each_with_index.map { |text, i| [i.zero? ? label : '', text] }
      }

      { rows: rows, entries: entries }
    end
  end
end

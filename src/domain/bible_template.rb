module Domain
  module BibleTemplate
    # {token} 對應到查詢來源，索引對應 entry[:texts] 的位置，
    # 順序必須跟 Domain::BibleQuery.run 裡 sources 陣列的順序一致
    SOURCE_TOKENS = {
      'local' => 0, # 麥可陳(cuv2)
      'fhl'   => 1, # 信望愛聖經資源中心(和合本)
      'niv'   => 2, # BibleGateway(NIV)（英語，未來會加 kjv）
      'gae'   => 3, # holybible.or.kr(개역개정)
    }.freeze

    # 不查經文來源、而是從節資訊本身算出來的 token
    COMPUTED_TOKENS = %w[verse chapter book_c book_e book_k].freeze

    # 把範本文字切成一段一段的 #<NAME_OF_REGION> 區塊，回傳 [[名稱, 內容], ...]
    # 名稱是 osascript 拿去比對 Keynote text object placeholder 用的
    def self.parse(text)
      text.scan(/#(\S+)(.*?)(?=#\S+|\z)/m).map { |name, body| [name, body.strip] }
    end

    # 把單一 #<NAME_OF_REGION> 的範本內容替換成實際內容
    # entry 是 Domain::BibleQuery.run 回傳的 entries 其中一筆：{ book:, chapter:, verse:, texts: [...] }
    # 找不到 token、或 token 對應的來源/資訊拿不到，都算錯誤，記錄到 errors 並在內文標示出來
    def self.render_placeholder(body, entry, errors, placeholder_name)
      info = Domain::Bible.chapter_info(entry[:book])
      location = "#{info && info[:chinese]}#{entry[:chapter]}:#{entry[:verse]}"

      rendered = body.gsub(/\{(\w+)\}/) do
        token = Regexp.last_match(1)
        value = resolve_token(token, entry, info)

        if value
          value
        elsif SOURCE_TOKENS.key?(token)
          errors << "#{location} ##{placeholder_name}：來源 {#{token}} 沒有經文（可能沒勾選查詢或查無結果）"
          "⚠️{#{token}}"
        elsif COMPUTED_TOKENS.include?(token)
          errors << "#{location} ##{placeholder_name}：無法取得 {#{token}}（找不到書卷資料）"
          "⚠️{#{token}}"
        else
          errors << "#{location} ##{placeholder_name}：未知的 token {#{token}}"
          "⚠️{#{token}}"
        end
      end

      rendered.gsub('\n', "\n")
    end

    def self.resolve_token(token, entry, info)
      case token
      when 'verse'   then entry[:verse].to_s
      when 'chapter' then entry[:chapter].to_s
      when 'book_c' then info && info[:chinese]
      when 'book_e' then info && info[:english]
      when 'book_k' then info && info[:korean]
      else
        idx = SOURCE_TOKENS[token]
        return nil if idx.nil?

        value = entry[:texts][idx]
        value && !value.empty? ? value : nil
      end
    end
  end
end

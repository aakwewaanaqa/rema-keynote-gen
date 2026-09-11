module Domain
  module BibleTemplate
    # 以下列出 {token} 之所對應的內容
    # {中}/{cuv}       - 信望愛經節內容
    # {英}/{niv}       - Biblegateway NIV 經節內容
    # {英王}/{kjv}     - Biblegateway KJV 經節內容
    # {新英王}/{nkjv}  - Biblegateway NKJV 經節內容
    # {韓}/{gae}       - Holynet 개역개장 經節內容
    # {中書}/{cb} - 中文書名
    # {英書}/{eb} - 英文書名
    # {韓書}/{kb} - 韓文書名
    # {章}/{ch}   - 章次
    # {節}/{vr}   - 節次
    # {token} 對應到查詢來源，索引對應 entry[:texts] 的位置，
    # 順序必須跟 Domain::BibleQuery.run 裡 sources 陣列的順序一致
    SOURCE_TOKENS = {
      'local' => 0, # 麥可陳(cuv2)
      'fhl'   => 1, # 信望愛聖經資源中心(和合本)
      'niv'   => 2, # BibleGateway(NIV)
      'gae'   => 3, # holybible.or.kr(개역개정)
      'nkjv'  => 4, # BibleGateway(NKJV)
      'kjv'   => 5, # BibleGateway(KJV)
    }.freeze

    # 不查經文來源、而是從節資訊本身算出來的 token
    COMPUTED_TOKENS = %w[verse chapter book_c book_e book_k].freeze

    # 好記的別名 -> 實際 token。{中}/{cuv} 對到信望愛(fhl)，不是 local，
    # 因為使用者習慣把「中文」跟信望愛的和合本聯想在一起，跟 local 的 cuv2 是兩回事
    ALIASES = {
      '中'   => 'fhl',
      'cuv'  => 'fhl',
      '英'   => 'niv',
      '韓'   => 'gae',
      '英王' => 'kjv',  # King James
      '新英王' => 'nkjv', # New King James，跟 {英王} 分開避免混淆
      '中書' => 'book_c',
      'cb'   => 'book_c',
      '英書' => 'book_e',
      'eb'   => 'book_e',
      '韓書' => 'book_k',
      'kb'   => 'book_k',
      '章'   => 'chapter',
      'ch'   => 'chapter',
      '節'   => 'verse',
      'vr'   => 'verse',
    }.freeze

    # 把別名代換回實際 token，不是別名就原樣傳回
    def self.canonical_token(token)
      ALIASES[token] || token
    end

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

      # \w 不吃中文字，別名（{中}/{章}/{節}...）都是中文，所以用「不是大括號的任何字元」來抓 token 名稱
      rendered = body.gsub(/\{([^{}]+)\}/) do
        raw_token = Regexp.last_match(1)
        token = canonical_token(raw_token)
        value = resolve_token(token, entry, info)

        if value
          value
        elsif SOURCE_TOKENS.key?(token)
          errors << "#{location} ##{placeholder_name}：來源 {#{raw_token}} 沒有經文（可能沒勾選查詢或查無結果）"
          "⚠️{#{raw_token}}"
        elsif COMPUTED_TOKENS.include?(token)
          errors << "#{location} ##{placeholder_name}：無法取得 {#{raw_token}}（找不到書卷資料）"
          "⚠️{#{raw_token}}"
        else
          errors << "#{location} ##{placeholder_name}：未知的 token {#{raw_token}}"
          "⚠️{#{raw_token}}"
        end
      end

      rendered.gsub('\n', "\n")
    end

    # token 這裡一律是已經過 canonical_token 代換過的實際 token，不會再收到別名
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

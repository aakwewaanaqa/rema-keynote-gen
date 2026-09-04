def advanced_bible_query_window
  include Glimmer

  # token 順序要跟 Domain::BibleTemplate::SOURCE_TOKENS 的 index 對齊，
  # 因為 Domain::BibleQuery.run 是用陣列位置對應每個來源
  token_sources = [
    ['local', Service::GithubMichaelChanBible],
    ['fhl',   Service::SpringBibleService],
    ['niv',   Service::BibleGatewayService],
    ['gae',   Service::HolyBibleKoreanService],
  ]

  search_field = nil
  query_button = nil
  status_label = nil
  progress_indicator = nil
  format_field = nil
  preview_field = nil

  latest_query_id = 0

  # 把上次查詢到的 entries 依目前格式框內容代換、顯示到預覽區
  # #<NAME_OF_REGION> 只是給 osascript 比對 Keynote placeholder 用的標記，跟內文無關，
  # 所以預覽只顯示代換後的內容本身，不把 #name 或節號標籤混進去，直接就是可以複製使用的樣子
  render_preview = -> (sections, entries) {
    errors = []
    blocks = entries.flat_map { |entry|
      sections.map { |name, body| Domain::BibleTemplate.render_placeholder(body, entry, errors, name) }
    }

    preview_field.text = blocks.join("\n\n")
    status_label.text = errors.empty? ? "共 #{entries.size} 節，預覽已產生" : "預覽含 #{errors.size} 個錯誤：\n#{errors.join("\n")}"
  }

  # 不再用勾選框選來源，直接掃格式框裡用到哪些 {token}，需要哪個來源就查哪個
  # 查詢跟產生預覽合成一個按鈕：查完直接用查到的結果套用目前的格式，不用再按第二次
  run_query = -> {
    raw_text = search_field.text.dup.force_encoding('UTF-8')
    format_text = format_field.text.dup.force_encoding('UTF-8')
    sections = Domain::BibleTemplate.parse(format_text)

    if sections.empty?
      status_label.text = '格式錯誤：找不到任何 #region 區塊（範例："#sec1 {fhl}"）'
      preview_field.text = ''
      next
    end

    used_tokens = sections.flat_map { |_, body| body.scan(/\{(\w+)\}/).flatten }.uniq
    sources = token_sources.map { |token, service| [used_tokens.include?(token), service] }

    if sources.none? { |enabled, _| enabled }
      status_label.text = "格式裡沒有用到任何經文來源 token（可用: #{token_sources.map(&:first).join('/')}）"
      preview_field.text = ''
      next
    end

    query_id = (latest_query_id += 1)

    status_label.text = '查詢中...'
    query_button.enabled = false
    progress_indicator.value = -1 # -1 讓 libui 顯示不確定進度的跑動動畫

    Thread.new do
      outcome = begin
        Domain::BibleQuery.run(raw_text, sources)
      rescue => e
        { error: e.message }
      end

      Glimmer::LibUI.queue_main do
        query_button.enabled = true
        progress_indicator.value = 0
        next if query_id != latest_query_id

        if outcome[:error]
          status_label.text = "查詢失敗: #{outcome[:error]}"
          preview_field.text = ''
        else
          render_preview.(sections, outcome[:entries])
        end
      end
    end
  }

  window('進階查詢', 900, 700) {
    margined true

    vertical_box {
      search_entry { |e|
        search_field = e
        stretchy false
        label '搜尋經節序號'
        text '太18:18-20'
      }

      label("#<NAME_OF_REGION> 給 osascript 比對 Keynote placeholder；\\n 換行；會依用到的 token 自動查對應來源") {
        stretchy false
      }

      label("來源: {local}麥可陳 {fhl}信望愛 {niv}BibleGateway {gae}개역개정") {
        stretchy false
      }

      label("節資訊: {verse}節次 {chapter}章次 {book_c}書名中文 {book_e}書名英文 {book_k}書名韓文") {
        stretchy false
      }

      format_field = entry { |e|
        stretchy false
        text '#sec1 {book_c}{verse} {fhl} \n {niv}\n#sec2 {gae}'
      }

      button('查詢並產生預覽') { |b|
        query_button = b
        stretchy false
        on_clicked { run_query.() }
      }

      progress_indicator = progress_bar { |p|
        stretchy false
        value 0
      }

      label('') { |l|
        status_label = l
        stretchy false
      }

      preview_field = multiline_entry { |e|
        stretchy true
        read_only true
      }
    }
}.show
end

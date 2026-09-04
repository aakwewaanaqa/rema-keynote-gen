require_relative "../../src/shared/readable_pos"
require_relative "../../src/shared/string_consumer"
require_relative "../../src/shared/token"
require_relative "../../src/shared/token_consumer"
require_relative "../../src/domain/bible"
require_relative "../../src/domain/search_dsl/ast"
require_relative "../../src/domain/search_dsl/tokenize"
require_relative "../../src/service/github_micheal_chan_bible.s"
require_relative "../../src/service/spring_bible.s"
require_relative "../../src/service/bible_gateway_service.s"
require_relative "../../src/service/holy_bible_korean_service.s"
require "glimmer-dsl-libui"

def lookup_bible_window
  include Glimmer

  search_field = nil
  query_button = nil
  status_label = nil
  result_table = nil
  local_checkbox = nil
  spring_checkbox = nil
  gateway_checkbox = nil
  korean_checkbox = nil

  # table 儲存格是單行顯示，把多語言塞進同一格的換行會被截斷，
  # 所以改成每個語言各自佔一列，同一節的列連續排在一起，節號只在該節第一列顯示，避免重複又能一眼看出分組

  # 查詢會打網路，不適合每次按鍵/勾選就觸發；改成按下查詢按鈕才送出，
  # 並丟到背景 thread 執行避免卡住 UI，用 query_id 忽略中途過期的查詢結果
  latest_query_id = 0

  run_query = -> {
    raw_text = search_field.text.dup.force_encoding('UTF-8')
    query_id = (latest_query_id += 1)

    sources = [
      [local_checkbox,   Service::GithubMichaelChanBible],
      [spring_checkbox,  Service::SpringBibleService],
      [gateway_checkbox, Service::BibleGatewayService],
      [korean_checkbox,  Service::HolyBibleKoreanService],
    ]

    status_label.text = '查詢中...'
    query_button.enabled = false

    Thread.new do
      outcome = begin
        ast = Domain::SearchDsl::Ast.parse raw_text
        # 同一節經文，各語言來源合併成同一列，而不是各自分開列出
        texts_by_verse = Hash.new { |h, k| h[k] = Array.new(sources.size, '') }

        sources.each_with_index do |(checkbox, service), idx|
          next unless checkbox.checked?

          service.query(ast).each do |v|
            texts_by_verse[v.verse][idx] = v.text
          end
        end

        rows = texts_by_verse.sort.flat_map { |verse, texts|
          non_empty = texts.reject(&:empty?)
          non_empty.each_with_index.map { |text, i| [i.zero? ? verse.to_s : '', text] }
        }

        { rows: rows }
      rescue => e
        { error: e.message }
      end

      Glimmer::LibUI.queue_main do
        query_button.enabled = true
        next if query_id != latest_query_id # 已經有更新的查詢在跑，這次結果過期了，不覆蓋畫面

        if outcome[:error]
          status_label.text = "查詢失敗: #{outcome[:error]}"
          result_table.cell_rows = []
        else
          status_label.text = "共 #{outcome[:rows].size} 列，點選任一列可複製該列經文"
          result_table.cell_rows = outcome[:rows]
        end
      end
    end
  }

  window('查聖經', 900, 600) {
    margined true

    vertical_box {
      search_entry { |e|
        search_field = e
        stretchy false
        label '搜尋經節序號'
        text '太18:18-20'
      }

      horizontal_box {
        stretchy false

        checkbox('麥可陳(cuv2)') { |c|
          local_checkbox = c
          stretchy false
        }

        checkbox('信望愛聖經資源中心(和合本)') { |c|
          spring_checkbox = c
          checked true
          stretchy false
        }

        checkbox('BibleGateway(NIV)') { |c|
          gateway_checkbox = c
          stretchy false
        }

        checkbox('holybible.or.kr(개역개정)') { |c|
          korean_checkbox = c
          stretchy false
        }
      }

      button('查詢') { |b|
        query_button = b
        stretchy false
        on_clicked { run_query.() }
      }

      label('') { |l|
        status_label = l
        stretchy false
      }

      result_table = table {
        text_column('節')
        text_column('經文')

        cell_rows []
        selection_mode :zero_or_one
        stretchy true

        on_row_clicked do |_t, row|
          row_data = result_table.cell_rows[row]
          next unless row_data

          IO.popen('pbcopy', 'w') { |io| io.write(row_data.last) }
          status_label.text = '已複製到剪貼簿'
        end
      }
    }
}.show
end

include Glimmer
window('首頁', 100, 200) {
  margined true

  vertical_box {
    vertical_box { stretchy true }
    button("查聖經") {
      on_clicked {
        lookup_bible_window
      }
    }
    button("批次製作") {
    }
    vertical_box { stretchy true }
  }
}.show
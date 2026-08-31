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

  bible_entry = nil
  search_field = nil
  query_button = nil
  local_checkbox = nil
  spring_checkbox = nil
  gateway_checkbox = nil
  korean_checkbox = nil

  # 查詢會打網路，不適合每次按鍵/勾選就觸發；改成按下查詢按鈕才送出，
  # 並丟到背景 thread 執行避免卡住 UI，用 query_id 忽略中途過期的查詢結果
  latest_query_id = 0

  run_query = -> {
    raw_text = search_field.text.dup.force_encoding('UTF-8')
    query_id = (latest_query_id += 1)

    services = [
      [local_checkbox,   Service::GithubMichaelChanBible, 'cuv2'],
      [spring_checkbox,  Service::SpringBibleService,     '網路版'],
      [gateway_checkbox, Service::BibleGatewayService,    'NIV'],
      [korean_checkbox,  Service::HolyBibleKoreanService, '개역개정'],
    ].select { |checkbox, _service, _tag| checkbox.checked? }

    bible_entry.text = '查詢中...'
    query_button.enabled = false

    Thread.new do
      result = begin
        ast = Domain::SearchDsl::Ast.parse raw_text
        services.flat_map { |_checkbox, service, tag|
          service.query(ast).map { |r| "[#{tag}] #{r.verse} #{r.text}" }
        }.join("\n")
      rescue => e
        "查詢失敗: #{e.message}"
      end

      Glimmer::LibUI.queue_main do
        query_button.enabled = true
        next if query_id != latest_query_id # 已經有更新的查詢在跑，這次結果過期了，不覆蓋畫面

        bible_entry.text = result
      end
    end
  }

  window('查聖經', 500, 600) {
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

      button('複製經文') {
        stretchy false
        on_clicked {
          IO.popen('pbcopy', 'w') { |io| io.write(bible_entry.text) }
        }
      }

      multiline_entry { |e|
        bible_entry = e
        stretchy true
        read_only true
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
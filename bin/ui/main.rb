require_relative "../../src/shared/readable_pos"
require_relative "../../src/shared/string_consumer"
require_relative "../../src/shared/token"
require_relative "../../src/shared/token_consumer"
require_relative "../../src/domain/bible"
require_relative "../../src/domain/search_dsl/ast"
require_relative "../../src/domain/search_dsl/tokenize"
require_relative "../../src/domain/bible_query"
require_relative "../../src/domain/bible_template"
require_relative "../../src/service/github_micheal_chan_bible.s"
require_relative "../../src/service/spring_bible.s"
require_relative "../../src/service/bible_gateway_service.s"
require_relative "../../src/service/holy_bible_korean_service.s"
require "glimmer-dsl-libui"

require_relative "windows/lookup_bible_window"
require_relative "windows/advanced_bible_query_window"

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
    button("進階查詢") {
      on_clicked {
        advanced_bible_query_window
      }
    }
    button("批次製作") {
    }
    vertical_box { stretchy true }
  }
}.show

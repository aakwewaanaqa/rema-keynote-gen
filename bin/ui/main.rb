require_relative "../../src/shared/reactive_state"
require_relative "../../src/service/github_micheal_chan_bible.s"
require "glimmer-dsl-libui"

def lookup_bible_window
  include Glimmer

  result = nil
  search_input = ::Shared::ReactiveState.new(
    nil,
    nil,
    -> old_val, new_val, changed {
      return unless changed
      ast = Domain::SearchDsl::Ast.parse new_val
      result = Domain::Service::GithubMichaelChanBible.qeury ast
    }
  )

  window('查聖經', 300, 400) {
    margined true

    vertical_box {
      search_entry { |e|
        stretchy false
        label '搜尋經節序號'
        text '太18:18-20'

        on_changed {
          search_input.set e.text
        }
      }

      multiline_entry { |e|
        text 
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
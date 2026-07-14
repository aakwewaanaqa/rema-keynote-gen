require_relative "../../src/shared/reactive_state"
require "glimmer-dsl-libui"

def lookup_bible_window
  include Glimmer
  q_state = ::Shared::ReactiveState.new(
    nil,
    nil,
    -> old_val, new_val, changed {
      puts new_val if changed
    }
  )

  window('查聖經', 300, 400) {
    margined true

    vertical_box {
      search_entry { |q|
        stretchy false
        label '搜尋經節序號'
        text '太18:18-20'

        on_changed {
          q_state.set q.text
        }
      }
    }
}.show
end

include Glimmer
window('簡報生成/首頁', 100, 200) {
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
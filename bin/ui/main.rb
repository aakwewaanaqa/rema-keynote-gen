require "glimmer-dsl-libui"

include Glimmer

window('簡報生成/首頁', 100, 200) {
  margined true
  vertical_box {
    vertical_box { stretchy true }
    button("查聖經") {
      on_clicked {
        msg_box('a', 'b')
      }
    }
    button("批次製作") {
    }
    vertical_box { stretchy true }
  }
}.show
# 手動示範腳本，不是 minitest 斷言測試：印出 KeynoteOsaDsl 組出來的 AppleScript 給人眼看。
# 原本放在 src/domain/keynote_osa_dsl/test.rb，但 src/src.rb 是用
# Dir[.../domain/**/*.rb] 整包 require 進來，害這支腳本的 top-level `puts`
# 每次 require src/src.rb（例如其他測試檔）都會被跑到，把 AppleScript 字串混進 stdout。
# 搬來 tests/ 底下、跳出 domain 的 glob 範圍，並改成手動執行：
#   ruby tests/manual_keynote_osa_dsl_demo.rb
require_relative '../src/domain/keynote_osa_dsl/open_keynote_app'

include Domain
include KeynoteOsaDsl

puts TellApp.new().here_doc {
  delay 3
  state(TellDocument, []) {
    clear_all_slides
    state(TellNewSlide, ["母片"]) {
      state(TellEveryTextItem, []) {
        replace_placeholder("中章", "創世記")
      }
    }
    delete_slide 1
  }
}

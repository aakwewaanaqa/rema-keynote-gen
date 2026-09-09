require_relative "open_keynote_app"

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
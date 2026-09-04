module Service
  BibleQueryVerse = Struct.new(
    :book,    # 書卷代碼（Domain::Bible::CHAPTERS 裡的 :code），如 :Matthew
    :chapter,
    :verse,
    :text,
  )
end
module Domain
  module Interpret
    # 將章節硬編碼轉成純序號，1-based 從創世記起算
    def self.pure_index chapter_code, chapter_offset
      i = 0
      ::Domain::Bible::CHAPTERS.each { |chapter|
        break if chapter[:code] == chapter_code
        i += chapter[:max]
      }

      i + chapter_offset
    end
  end
end
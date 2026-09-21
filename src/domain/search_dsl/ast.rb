module Domain
  module SearchDsl
    # AST（Abstract Syntax Tree，抽象語法樹）
    #
    # 使用者輸入的聖經查詢字串（如「太1:1-5,7;創3:7」）需要先被 Tokenize 切成 token 序列，
    # 再由這裡的 Parser 把 token 序列組成一棵樹狀結構。
    #
    # 為什麼要樹狀結構？
    #   因為字串本身無法直接被程式使用。樹狀結構把「意圖」抽離出來，
    #   讓後續的服務（cuv1 本地檔案、spring_bible 網路 API）可以各自實作
    #   「拿著這棵樹去查詢」，而不需要重複解析字串。
    #
    # 這裡的樹只有三層深：
    #   Query                          ← 整個查詢（可能包含多個書卷）
    #     └─ [BibleRef, BibleRef ...]  ← 每個書卷+章的查詢單元
    #          └─ [Single | VRange ...] ← 該章裡要取的節
    #
    # 範例：「太1:1-5,7;創3:7」會被解析成：
    #
    #   Query
    #   ├─ BibleRef { book: :Matthew, chapter: 1, verses: [
    #   │    VRange { from: 1, to: 5 },   ← 1-5
    #   │    Single { verse: 7 }           ← 7
    #   │  ]}
    #   └─ BibleRef { book: :Genesis, chapter: 3, verses: [
    #        Single { verse: 7 }           ← 7
    #      ]}
    #
    # 文法（BNF）：
    #   Query        = BibleRefGroup (';' BibleRefGroup)*
    #   BibleRefGroup = IDENTIFIER ChapterVerses (',' ChapterVerses)*   ← 展開成多個 BibleRef
    #   ChapterVerses = NUMBER (':' VerseList)?
    #   VerseList    = VerseItem (',' VerseItem)*
    #   VerseItem    = NUMBER ('-' NUMBER)?
    #
    # BibleRefGroup 的逗號分支只在「逗號後面接著 數字:數字」時才成立（換章），
    # 否則逗號屬於 VerseList，代表同一章的下一節，例如「創2:15,3:6」＝ 創2:15 + 創3:6，
    # 但「太1:1-5,7」的逗號是同一章多一節，不是換到第 7 章。
    #
    # Parser 採「遞迴下降」(recursive descent) 策略：
    #   每條文法規則對應一個 lambda，從左到右消耗 token，
    #   遇到符合的就推進（advance），不符合就回傳 nil 讓上層決定如何處理。
    module Ast
      Query    = Struct.new(:refs)                    # refs: [BibleRef]
      BibleRef = Struct.new(:book, :chapter, :verses) # verses 為 nil 代表整章
      Single   = Struct.new(:verse)                   # 單節
      VRange   = Struct.new(:from, :to)               # 連續範圍，如 1-5

      # NUMBER ('-' NUMBER)?  →  Single | VRange
      PARSE_VERSE_ITEM = -> tc {
        return nil unless tc.sneak_peek&.last == :number
        from = tc.advance.text.to_i
        if tc.sneak_peek&.last == :hyphen
          tc.advance
          to_num = tc.advance&.text&.to_i
          VRange.new(from, to_num)
        else
          Single.new(from)
        end
      }

      # VerseItem (',' VerseItem)*
      PARSE_VERSE_LIST = -> tc {
        items = []
        item = PARSE_VERSE_ITEM.(tc)
        return nil if item.nil?
        items << item
        # 逗號後面若是「數字:數字」代表換章（見 CHAPTER_SWITCH_AHEAD），
        # 那個逗號要留給 PARSE_BIBLE_REF_GROUP 處理，節清單在這裡就要停止
        while tc.sneak_peek&.last == :comma && !CHAPTER_SWITCH_AHEAD.(tc)
          tc.advance
          item = PARSE_VERSE_ITEM.(tc)
          items << item if item
        end
        items
      }

      # NUMBER (':' VerseList)?
      PARSE_CHAPTER_VERSES = -> tc {
        return nil unless tc.sneak_peek&.last == :number
        chapter = tc.advance.text.to_i

        verses = nil
        if tc.sneak_peek&.last == :colon
          tc.advance
          verses = PARSE_VERSE_LIST.(tc)
        end

        { chapter: chapter, verses: verses }
      }

      # 逗號後面接著「數字 冒號」才代表換章（如 2:15,3:6 的 ',3:6'），
      # 不消耗 token，只是往後看，讓呼叫端決定逗號到底屬於 VerseList 還是換章
      CHAPTER_SWITCH_AHEAD = -> tc {
        tc.sneak_peek&.last == :comma &&
          tc.peek_at(1)&.last == :number &&
          tc.peek_at(2)&.last == :colon
      }

      # IDENTIFIER ChapterVerses (',' ChapterVerses)*  →  [BibleRef, ...]
      # IDENTIFIER 交給 MATCH_CHAPTER 解析，支援中文全名、中文縮寫、英文全名、英文縮寫。
      # 回傳陣列是因為一個書名可以展開成好幾個不同章的 BibleRef（換章逗號的緣故）。
      PARSE_BIBLE_REF_GROUP = -> tc {
        return [] unless tc.sneak_peek&.last == :identifier
        book_token = tc.advance

        chapter_info = ::Domain::Bible::MATCH_CHAPTER.(book_token.text)
        return [] if chapter_info.nil? # 識別不出書卷就跳過整個 ref
        book_code = chapter_info[:code]

        first = PARSE_CHAPTER_VERSES.(tc)
        return [] if first.nil?
        refs = [BibleRef.new(book_code, first[:chapter], first[:verses])]

        while CHAPTER_SWITCH_AHEAD.(tc)
          tc.advance # 換章的逗號
          cv = PARSE_CHAPTER_VERSES.(tc)
          refs << BibleRef.new(book_code, cv[:chapter], cv[:verses]) if cv
        end

        refs
      }

      # BibleRefGroup (';' BibleRefGroup)*
      # 換行在 tokenize 階段已經被轉成 :semicolon（見 tokenize.rb 的 DO_LINE_BREAK），
      # 所以「一行一筆」的輸入到這裡跟打「;」分隔是同一種 token，不用另外處理。
      PARSE = -> tc {
        refs = PARSE_BIBLE_REF_GROUP.(tc)
        return Query.new([]) if refs.empty?
        while tc.sneak_peek&.last == :semicolon
          tc.advance
          refs.concat(PARSE_BIBLE_REF_GROUP.(tc))
        end
        Query.new(refs)
      }

      # 節號是否落在 verses 清單（Single | VRange 混合）之中
      def self.verse_in_list?(verse_num, verse_list)
        verse_list.any? do |v|
          case v
          when Single then v.verse == verse_num
          when VRange then verse_num >= v.from && (v.to.nil? || verse_num <= v.to)
          end
        end
      end

      # 入口：字串 → Query AST
      def self.parse(str)
        sc = ::Shared::StringConsumer.new(str)
        tokens = ::Domain::SearchDsl::Tokenize::TOKENIZE.(sc)
        tc = ::Shared::TokenConsumer.new(tokens)
        PARSE.(tc)
      end
    end
  end
end

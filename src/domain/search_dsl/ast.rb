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
    #   Query      = BibleRef (';' BibleRef)*
    #   BibleRef   = IDENTIFIER NUMBER (':' VerseList)?
    #   VerseList  = VerseItem (',' VerseItem)*
    #   VerseItem  = NUMBER ('-' NUMBER)?
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
        while tc.sneak_peek&.last == :comma
          tc.advance
          item = PARSE_VERSE_ITEM.(tc)
          items << item if item
        end
        items
      }

      # IDENTIFIER NUMBER (':' VerseList)?
      # IDENTIFIER 交給 MATCH_CHAPTER 解析，支援中文全名、中文縮寫、英文全名、英文縮寫
      PARSE_BIBLE_REF = -> tc {
        return nil unless tc.sneak_peek&.last == :identifier
        book_token = tc.advance
        return nil unless tc.sneak_peek&.last == :number
        chapter = tc.advance.text.to_i

        chapter_info = ::Domain::Bible::MATCH_CHAPTER.(book_token.text)
        return nil if chapter_info.nil? # 識別不出書卷就跳過整個 ref
        book_code = chapter_info[:code]

        verses = nil
        if tc.sneak_peek&.last == :colon
          tc.advance
          verses = PARSE_VERSE_LIST.(tc)
        end

        BibleRef.new(book_code, chapter, verses)
      }

      # BibleRef (';' BibleRef)*
      PARSE = -> tc {
        refs = []
        ref = PARSE_BIBLE_REF.(tc)
        return Query.new([]) if ref.nil?
        refs << ref
        while tc.sneak_peek&.last == :semicolon
          tc.advance
          ref = PARSE_BIBLE_REF.(tc)
          refs << ref if ref
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

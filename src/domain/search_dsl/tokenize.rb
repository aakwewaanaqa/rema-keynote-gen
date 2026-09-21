module Domain
  module SearchDsl
    module Tokenize
      DO_IDENTIFIER = -> sc {
        return nil if sc.nil? || sc.done?

        pos = sc.readable_pos
        text = ''
        while peak_match = sc.match_advance(/[^\d\s,，、:：;；\-−—－~～]/)
          text << peak_match.to_s
        end

        if text.length > 0
          return ::Shared::Token.new(
            :identifier,
            text,
            pos
          )
        end

        nil
      }

      DO_COMMA = -> sc {
        return nil if sc.nil? || sc.done?

        pos = sc.readable_pos
        if match_peak = sc.match_advance(/[,，、]/)
          return ::Shared::Token.new(
            :comma,
            ',',
            pos
          )
        end

        return nil
      }

      DO_COLON = -> sc {
        return nil if sc.nil? || sc.done?

        pos = sc.readable_pos
        if match_peak = sc.match_advance(/[:：]/)
          return ::Shared::Token.new(
            :colon,
            ':',
            pos
          )
        end

        return nil
      }

      DO_SEMICOLON = -> sc {
        return nil if sc.nil? || sc.done?

        pos = sc.readable_pos
        if match_peak = sc.match_advance(/[;；]/)
          return ::Shared::Token.new(
            :semicolon,
            ';',
            pos
          )
        end

        return nil
      }

      DO_HYPHEN = -> sc {
        return nil if sc.nil? || sc.done?

        pos = sc.readable_pos
        if match_peak = sc.match_advance(/[\-−—－\-−~～]/)
          return ::Shared::Token.new(
            :hyphen,
            '-',
            pos
          )
        end

        return nil
      }

      DO_NUMBER = -> sc {
        return nil if sc.nil? || sc.done?

        pos = sc.readable_pos
        text = ''
        while peak_match = sc.match_advance(/\d/)
          text << peak_match.to_s
        end

        if text.length > 0
          return ::Shared::Token.new(
            :number,
            text,
            pos
          )
        end

        return nil
      }

      # 換行等同分號：貼上「一行一筆」的查詢（如「啟示錄3:7-8\n使徒行傳5:19」）時，
      # 換行就是使用者拿來分隔不同筆查詢的符號，跟打「;」的意思一樣，直接轉成 :semicolon，
      # ast.rb 的 PARSE 完全不用另外處理換行。順便吃掉換行前後的空白，避免多留下沒用的 token。
      DO_LINE_BREAK = -> sc {
        return nil if sc.nil? || sc.done?

        pos = sc.readable_pos
        if sc.match_advance(/[ \t\r\n　]*[\r\n][ \t\r\n　]*/)
          return ::Shared::Token.new(
            :semicolon,
            ';',
            pos
          )
        end

        return nil
      }

      # 空格、全形空格、tab（不含換行，換行由 DO_LINE_BREAK 處理）不帶任何意義，
      # 純粹是使用者排版習慣（例如「路加福音 19:3-5」書名跟章節間的空格），直接跳過不產生 token。
      SKIP_WHITESPACE = -> sc {
        return false if sc.nil? || sc.done?
        !!sc.match_advance(/[ \t　]+/)
      }

      TOKENIZE = -> sc {
        tokens = []
        until sc.done?
          next if SKIP_WHITESPACE.(sc)

          token =
            DO_LINE_BREAK.(sc) ||
            DO_NUMBER.(sc)    ||
            DO_COMMA.(sc)     ||
            DO_COLON.(sc)     ||
            DO_SEMICOLON.(sc) ||
            DO_HYPHEN.(sc)    ||
            DO_IDENTIFIER.(sc)

          if token
            tokens << token
          else
            pos = sc.readable_pos
            unknown = sc.advance
            tokens << ::Shared::Token.new(
              :unknown,
              unknown,
              pos
            )
          end
        end

        return tokens
      }
    end
  end
end
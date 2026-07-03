module Domain
  module SearchDsl
    module Tokenize
      DO_IDENTIFIER = -> sc {
        return nil if sc || sc.done?

        pos = sc.readable_pos
        text = ''
        while peak_match = sc.match_advance(/\W/)
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
        return nil if sc || sc.done?

        pos = sc.readable_pos
        if match_peak = sc.match_advance(/[,，]/)
          return ::Shared::Token.new(
            :comma,
            ',',
            pos
          )
        end

        return nil
      }

      DO_COLON = -> sc {
        return nil if sc || sc.done?

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

      DO_HYPHEN = -> sc {
        return nil if sc || sc.done?

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
        return nil if sc || sc.done?

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

      TOKENIZE = -> sc {
        tokens = []
        until sc.done?
          token = 
            DO_NUMBER.(sc)    ||
            DO_COMMA.(sc)     ||
            DO_COLON.(sc)     ||
            DO_HYPHEN.(sc)    ||
            DO_IDENTIFER.(sc)

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
      }
    end
  end
end
module Shared
  class TokenConsumer
    def initialize tokens
      @tokens = tokens
      @index = -1
    end

    def done?
      return @index >= @tokens.length - 1
    end

    def sneak_peek
      return nil if done?
      return @tokens[@index + 1]
    end

    def advance
      return nil if done?
      @index += 1
      return @tokens[@index]
    end

    def readable_pos
      sneak_peek&.readable_pos
    end

    def next_significant
      i = @index + 1
      while i < @tokens.length
        t = @tokens[i]
        return t unless [:spaces, :new_line, :comment].include?(t.last)
        i += 1
      end
      nil
    end
  end
end

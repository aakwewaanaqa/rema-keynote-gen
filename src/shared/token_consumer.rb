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

    # 看比 sneak_peek 更後面的 token，不會推進游標。offset 1 代表 sneak_peek 的下一個。
    # 用來在遇到分隔符時，不消耗它就先判斷後面的形狀，決定該分隔符代表什麼意思
    # （例如逗號後面接著「數字:數字」代表換章，接著單一數字則代表同一章的下一節）。
    def peek_at(offset)
      i = @index + 1 + offset
      return nil if i >= @tokens.length
      @tokens[i]
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

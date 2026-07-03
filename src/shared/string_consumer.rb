module Shared
  class StringConsumer
    attr_reader :literaling
    attr_reader :index
    attr_writer :readable_pos_offset

    def initialize str
      @str = str
      @index = -1         # 目前讀取位置（-1 表示尚未開始）
      @escaping = false
      @literaling = false # 目前在字串字面值內時記錄開頭引號（'、"、`），否則 false
      @readable_pos_offset = ReadablePos.new
    end

    # 目前字元是否被 \ 跳脫（連續偶數個 \ 視為互相抵消，不算跳脫）
    def peak_escaped?
      return false unless @literaling

      switch = false
      i = @index - 1
      while i >= 0 && @str[i] == '\\'
        switch = !switch
        i -= 1
      end

      return switch
    end

    def done?
      @index >= @str.length - 1
    end

    def rest
      return nil if done?
      @str[@index + 1..]
    end

    def sneak_peek
      return nil if done?
      return @str[@index + 1]
    end

    def match_sneak_peak candidates
      return nil if done?

      candidates.each do |pattern|
        return pattern if rest.start_with?(pattern)
      end

      return nil
    end

    def str_advance str
      return nil if done?
      raise TypeError unless str.is_a?(String)

      return nil unless rest.start_with? str

      @index += str.length
      return str
    end

    def match_advance pattern
      return nil if done?
      raise TypeError unless pattern.is_a?(Regexp)

      match = pattern.match(rest)
      return nil unless match&.pre_match&.empty?
      match[0].length.times { advance }
      match
    end

    # 前進一個字元，並更新 @literaling 狀態，回傳新位置的字元；超界回傳 nil
    def advance
      return nil if done?

      @index += 1
      peak = @str[@index]

      if !@literaling && (peak == "'" || peak == '"' || peak == '`')
        @literaling = peak
      elsif peak == @literaling && !peak_escaped?
        @literaling = false
      end

      return peak
    end

    def readable_pos
      return ((ReadablePos.new 1, 1) + @readable_pos_offset) if @index < 0

      line = 1 + @str[0..@index].count("\n")
      last_newline_index = @str.rindex("\n", @index) || -1
      column = @index - last_newline_index + 1
      pos = ReadablePos.new line, column
      pos += @readable_pos_offset
    end
  end
end

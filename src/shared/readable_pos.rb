module Shared
  class ReadablePos
    attr_accessor :line, :column

    def initialize line = 0, column = 0
      @line = line
      @column = column
    end

    def + readable_pos
      ReadablePos.new(self.line + readable_pos.line, self.column + readable_pos.column)
    end

    def to_s
      { line: @line, column: @column }.to_s
    end
  end
end
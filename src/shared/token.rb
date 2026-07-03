module Shared
  Token = Struct.new(:last, :text, :readable_pos) do
    def end_pos
      lines = text.split("\n", -1)
      if lines.length == 1
        ReadablePos.new(readable_pos.line, readable_pos.column + text.length - 1)
      else
        ReadablePos.new(readable_pos.line + lines.length - 1, lines.last.length)
      end
    end
  end
end
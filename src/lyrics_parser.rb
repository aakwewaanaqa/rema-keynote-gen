# frozen_string_literal: true

class LyricsParser
  Result = Struct.new(:line_count, :placeholders, :sections, keyword_init: true)

  def self.parse(path)
    new(File.readlines(path, chomp: true)).parse
  end

  def initialize(lines)
    @lines = lines
  end

  def parse
    line_count = 1
    placeholders = []
    sections = {}
    current_section = nil
    current_group = []

    @lines.each do |line|
      if line.start_with?("#!")
        key, value = line[2..].strip.split("=", 2)
        case key.strip
        when "line"         then line_count = value.to_i
        when "placeholders" then placeholders = value.split(",").map(&:strip)
        end

      elsif (m = line.match(/^# end (.+)$/))
        _ = m
        flush(sections, current_section, current_group)
        current_group = []
        current_section = nil

      elsif (m = line.match(/^# (.+)$/))
        current_section = m[1].strip
        sections[current_section] = []

      elsif line.empty?
        if current_section && !current_group.empty?
          flush(sections, current_section, current_group)
          current_group = []
        end

      else
        current_group << line if current_section
      end
    end

    flush(sections, current_section, current_group) if current_section && !current_group.empty?

    Result.new(line_count: line_count, placeholders: placeholders, sections: sections)
  end

  private

  def flush(sections, section, group)
    sections[section] << group.dup unless group.empty?
  end
end

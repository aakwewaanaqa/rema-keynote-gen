# frozen_string_literal: true

require 'fileutils'

class KeynoteRunner
  APP = "Keynote"

  def self.export(template:, slide_groups:, placeholders:, output_dir:)
    FileUtils.mkdir_p(output_dir)
    script = build_script(template, slide_groups, placeholders, output_dir)
    system("osascript", "-e", script)
  end

  def self.build_script(template, slide_groups, placeholders, output_dir)
    add_slides = slide_groups.map do |group|
      set_texts = placeholders.each_with_index.map do |ph, i|
        text = group[i] || ""
        <<~AS.strip
          if object text of t is equal to #{q(ph)} then
                  set object text of t to #{q(text)}
                end if
        AS
      end.join("\n                ")

      <<~AS
        set s to (make new slide)
        tell s
          repeat with t in every text item
            tell t
              #{set_texts}
            end tell
          end repeat
        end tell
      AS
    end.join("\n    ")

    <<~APPLESCRIPT
      tell application "#{APP}"
        open POSIX file #{q(template)}
        delay 2
        tell front document
          if (count of slides) > 1 then delete slides 2 thru (count of slides)
          #{add_slides}
          delete slide 1
          export to POSIX file #{q(output_dir)} as slide images with properties {image format:PNG}
          close saving no
        end tell
      end tell
    APPLESCRIPT
  end

  def self.q(str)
    "\"#{str.gsub("\\", "\\\\").gsub('"', '\\"')}\""
  end
  private_class_method :q
end

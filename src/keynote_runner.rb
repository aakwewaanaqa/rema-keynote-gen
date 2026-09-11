# frozen_string_literal: true

require 'fileutils'

class KeynoteRunner
  APP = "Keynote"

  # Keynote 的「export ... as slide images」會自己去建立匯出目標資料夾，如果那個資料夾已經存在
  # （例如使用者直接選了 output_dir 本身，這裡又先 mkdir_p 過一次）就會匯出失敗
  # （"could not be exported... changes might be lost"）。所以只確保 output_dir 這個「容器」存在，
  # 實際匯出目標另外取一個當下必定不存在的子資料夾名稱，交給 Keynote 自己建立。
  def self.export(template:, slide_groups:, placeholders:, output_dir:)
    FileUtils.mkdir_p(output_dir)
    export_dir = unique_export_dir(output_dir)
    script = build_script(template, slide_groups, placeholders, export_dir)
    success = system("osascript", "-e", script)
    { success: success, export_dir: export_dir }
  end

  def self.unique_export_dir(output_dir)
    base = File.join(output_dir, "keynote_export_#{Time.now.strftime('%Y%m%d_%H%M%S')}")
    dir = base
    suffix = 1
    while File.exist?(dir)
      dir = "#{base}_#{suffix}"
      suffix += 1
    end
    dir
  end
  private_class_method :unique_export_dir

  # 新投影片一定要沿用範本 slide 1 的 base slide（版型），不然 `make new slide` 會套用
  # 佈景主題的預設版型，裡面文字框的內容（如 "Title"/"Text"）跟 placeholders 打的字串對不上，
  # `if object text of t is equal to ...` 永遠比對失敗，投影片就會整張空白（沒有任何文字被替換進去）。
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
        set s to (make new slide with properties {base slide:baseLayout})
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
          set baseLayout to base slide of slide 1
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

# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

class KeynoteRunner
  APP = "Keynote"

  # Keynote 的「export ... as slide images」會自己去建立匯出目標資料夾，如果那個資料夾已經存在
  # （例如使用者直接選了 output_dir 本身，這裡又先 mkdir_p 過一次）就會匯出失敗
  # （"could not be exported... changes might be lost"）。所以只確保 output_dir 這個「容器」存在，
  # 實際匯出目標另外取一個當下必定不存在的子資料夾名稱，交給 Keynote 自己建立。
  # master_name 是範本裡的母片（slide layout）名稱，nil/空字串就沿用範本 slide 1 的母片（見 build_script 的說明）
  # keep_open_path 有給的話，範本改複製到這個路徑（不是暫存資料夾），產生完存檔並留在 Keynote 裡開著，
  # 讓使用者可以接著改、⌘S 也存得回這個檔；沒給就跟原本一樣用暫存複本、產生完不存檔直接關掉
  # export_images: false 就只貼投影片不匯出圖片，回傳的 export_dir 是 nil（只在 keep_open_path 有給時才有意義）
  def self.export(template:, slide_groups:, placeholders:, output_dir:, master_name: nil, keep_open_path: nil, export_images: true)
    FileUtils.mkdir_p(output_dir)
    export_dir = export_images ? unique_export_dir(output_dir) : nil
    success = if keep_open_path
                FileUtils.cp_r(template, keep_open_path)
                system("osascript", "-e", build_script(keep_open_path, slide_groups, placeholders, export_dir, master_name, keep_open: true))
              else
                with_template_copy(template) do |copy|
                  system("osascript", "-e", build_script(copy, slide_groups, placeholders, export_dir, master_name))
                end
              end
    { success: success, export_dir: export_dir }
  end

  # 列出範本裡所有母片名稱，給使用者挑 master_name 用。要真的叫 Keynote 開檔才讀得到，
  # 讀完就 close saving no。開的是暫存複本（見 with_template_copy），範本就算正開著也不會被關掉。
  # 名稱用 linefeed 串起來回傳（母片名稱不會含換行）
  def self.layout_names(template)
    output = nil
    success = with_template_copy(template) do |copy|
      script = <<~APPLESCRIPT
        tell application "#{APP}"
          set doc to open POSIX file #{q(copy)}
          delay 2
          tell doc
            set layoutNames to name of every slide layout
            close saving no
          end tell
        end tell
        set AppleScript's text item delimiters to linefeed
        return layoutNames as text
      APPLESCRIPT
      output = IO.popen(["osascript", "-e", script], &:read).force_encoding("UTF-8")
      $?.success?
    end
    return { success: false, names: [] } unless success

    { success: true, names: output.split("\n").map(&:strip).reject(&:empty?) }
  end

  # 列出 Keynote 目前開著、而且已經存過檔的文件（沒存過檔的沒有路徑，沒辦法拿來當範本），
  # 給使用者直接挑來當範本。Keynote 沒在跑就回傳空清單，不要為了問這個把 Keynote 叫起來。
  # 每份文件回傳 { path:, modified: }，modified 代表有未儲存的變更——範本走的是磁碟上的檔案，
  # 那些變更不會反映在產生的投影片上，呼叫端要提醒使用者先存檔。
  def self.open_documents
    script = <<~APPLESCRIPT
      if application "#{APP}" is not running then return ""
      set out to ""
      tell application "#{APP}"
        repeat with d in documents
          try
            set f to file of d
            if f is not missing value then
              set out to out & (POSIX path of f) & tab & ((modified of d) as text) & linefeed
            end if
          end try
        end repeat
      end tell
      return out
    APPLESCRIPT
    output = IO.popen(["osascript", "-e", script], &:read).force_encoding("UTF-8")
    return { success: false, documents: [] } unless $?.success?

    documents = output.split("\n").reject(&:empty?).map do |line|
      path, modified = line.split("\t")
      { path: path.chomp("/"), modified: modified == "true" }
    end
    { success: true, documents: documents }
  end

  # 範本開的一律是暫存資料夾裡的複本，不是範本本身：使用者可能正在 Keynote 裡開著同一個範本，
  # 直接 open 原檔的話 Keynote 只會把那份已開的文件拉到最前面，後面的刪投影片、close saving no
  # 就會作用在使用者自己的文件上，未儲存的修改直接不見。.key 有可能是資料夾形式的 package，所以用 cp_r。
  def self.with_template_copy(template)
    Dir.mktmpdir("keynote_template") do |dir|
      copy = File.join(dir, File.basename(template))
      FileUtils.cp_r(template, copy)
      yield copy
    end
  end
  private_class_method :with_template_copy

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
  # 有指定 master_name 就改用那張母片，前提一樣是那張母片裡的文字框內容要跟 placeholders 對得上。
  def self.build_script(template, slide_groups, placeholders, output_dir, master_name = nil, keep_open: false)
    base_layout = if master_name.nil? || master_name.empty?
                    "base slide of slide 1"
                  else
                    "slide layout #{q(master_name)}"
                  end

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
        #{keep_open ? 'activate' : ''}
        set doc to open POSIX file #{q(template)}
        delay 2
        tell doc
          if (count of slides) > 1 then delete slides 2 thru (count of slides)
          set baseLayout to #{base_layout}
          #{add_slides}
          delete slide 1
          #{output_dir ? "export to POSIX file #{q(output_dir)} as slide images with properties {image format:PNG}" : ''}
          #{keep_open ? 'save doc' : 'close saving no'}
        end tell
      end tell
    APPLESCRIPT
  end

  def self.q(str)
    "\"#{str.gsub("\\", "\\\\").gsub('"', '\\"')}\""
  end
  private_class_method :q
end

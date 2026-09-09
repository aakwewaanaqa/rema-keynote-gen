module Domain
  module KeynoteOsaDsl
    def q(str)
      "\"#{str.gsub("\\", "\\\\").gsub('"', '\\"')}\""
    end    

    class TellApp
      APP = "Keynote"

      attr_reader :indention

      def initialize(indention = "")
        @indention = indention
        @content = ""
      end

      def here_doc &block
        @content += "#{@indention}tell Application #{KeynoteOsaDsl.q(APP)}\n"
        self.instance_eval(&block)
        @content += "#{@indention}end tell\n"

        return @content
      end

      def open_file path
        @content += "#{@indention}  open POSIX file #{KeynoteOsaDsl.q(path)}\n"
      end

      def delay seconds
        @content += "#{@indention}  delay #{seconds}\n"
      end

      def state(statement_class, args, &block)
        instance = statement_class.send(:new, @indention + "  ", args)
        @content += instance.send(:here_doc, &block)
      end
    end

    class TellDocument
      attr_reader :indention

      def initialize(indention, args)
        @indention = indention
        @content = ""
      end

      def here_doc &block
        @content += "#{@indention}tell front Document\n"
        self.instance_eval(&block)
        @content += "#{@indention}end tell\n"

        return @content
      end

      def clear_all_slides
        @content += "#{@indention}  if (count of slides) > 1 then delete slides 2 thru (count of slides)\n"
      end

      def delete_slide idx
        @content += "#{@indention}  delete slide #{idx}\n"
      end

      def state(statement_class, args, &block)
        instance = statement_class.send(:new, @indention + "  ", args)
        @content += instance.send(:here_doc, &block)
      end

      def export_png output_dir
        @content += "#{@indention}  export to POSIX file #{KeynoteOsaDsl.q(output_dir)} as slide images with properties {image format:PNG}"
      end

      def close
        @content += "#{@indention}  close saving no"
      end
    end

    class TellNewSlide
      attr_reader :indention

      def initialize(indention, args)
        @indention = indention
        @args = args
        @content = ""
      end

      def here_doc &block
        @content += "#{@indention}set s to (make new slide with properties {base slide:slide layout \"#{@args.dig(0)}\"})\n"
        @content += "#{@indention}tell s\n"
        self.instance_eval(&block)
        @content += "#{@indention}end tell\n"

        return @content
      end

      def state(statement_class, args, &block)
        instance = statement_class.send(:new, @indention + "  ", args)
        @content += instance.send(:here_doc, &block)
      end
    end

    class TellEveryTextItem
      attr_reader :indention

      def initialize(indention, args)
        @indention = indention
        @args = args
        @content = ""
      end

      def here_doc &block
        @content += "#{@indention}repeat with t in every text item\n"
        @content += "#{@indention}  tell t\n"
        self.instance_eval(&block)
        @content += "#{@indention}  end tell\n"
        @content += "#{@indention}end repeat\n"

        return @content
      end

      def state(statement_class, args, &block)
        instance = statement_class.send(:new, @indention + "  ", args)
        @content += instance.send(:here_doc, &block)
      end

      def replace_placeholder ph, text
        @content += "#{@indention}    if object text of t is equal to #{KeynoteOsaDsl.q(ph)} then\n"
        @content += "#{@indention}      set object text of t to #{KeynoteOsaDsl.q(text)}\n"
        @content += "#{@indention}    end if\n"
      end
    end
  end
end
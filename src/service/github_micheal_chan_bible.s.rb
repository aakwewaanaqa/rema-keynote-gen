require 'pathname'
require_relative '../domain/bible'
require_relative '../domain/search_dsl/ast'
require_relative 'bible_query_verse'

module Service
  class GithubMichaelChanBible
    SRC_PATH = -> {
      p = File.absolute_path(__dir__)
      Pathname.new(p).parent().parent().join('bible_src')
    }.()

    def self.is_installed?
      File.exist?(SRC_PATH)
    end

    def self.install
      tag = '[GithubMichaelChanBible.install_locally.pwd]'

      wd = Dir.pwd
      Dir.chdir(SRC_PATH.parent())
      puts "#{tag} #{Dir.pwd}"
      eval '`git clone https://github.com/michaelchanwahyan/bible_src.git`'
      Dir.chdir(wd)
      puts "#{tag} #{Dir.pwd}"
    end

    # 輸入 Query AST，回傳 [{chapter:, verse:, text:}, ...]
    def self.query(query_ast, translation: 'cuv2')
      query_ast.refs.flat_map do |ref|
        stem = book_file_stem(ref.book)
        next [] unless stem

        file_path = SRC_PATH.join(translation, "#{stem}.txt")
        next [] unless File.exist?(file_path)

        lines = File.readlines(file_path, encoding: 'UTF-8')
        chapter_prefix = "#{ref.chapter}."
        chapter_lines = lines.select { |l| l.start_with?(chapter_prefix) }

        chapter_lines.filter_map do |line|
          v = parse_verse_line(line)
          next unless v
          next if ref.verses && !verse_in_list?(v[:verse], ref.verses)
          v
        end
      end
    end

    private

    # :Genesis → "Gen"（取最後一個 ASCII 縮寫，截 3 字元）
    def self.book_file_stem(book_code)
      chapter = Domain::Bible::CHAPTERS.find { |c| c[:code] == book_code }
      return nil unless chapter
      ascii = chapter[:acronyms].select { |a| a.match?(/\A[a-zA-Z0-9]+\z/) }
      ascii.last[0..2]
    end

    # "1.3 神說：..." → { chapter: 1, verse: 3, text: "神說：..." }
    def self.parse_verse_line(line)
      m = line.match(/\A(\d+)\.(\d+)\s+(.+)/)
      return nil unless m
      return ::Service::BibleQueryVerse.new(
        m[1].to_i,
        m[2].to_i,
        m[3].strip
      )
    end

    def self.verse_in_list?(verse_num, verse_list)
      verse_list.any? do |v|
        case v
        when Domain::SearchDsl::Ast::Single then v.verse == verse_num
        when Domain::SearchDsl::Ast::VRange then verse_num >= v.from && verse_num <= v.to
        end
      end
    end
  end
end

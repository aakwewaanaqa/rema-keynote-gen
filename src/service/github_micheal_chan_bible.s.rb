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
  end
end
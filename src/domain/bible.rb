module Domain
  module Bible
    BibleIndex = Struct.new(:code, :chapter, :verse) # 記得章節與經節是 1-based

    LEVENSHTEIN = -> (a, b) {
      m, n = a.length, b.length
      dp = Array.new(m + 1) { |i| Array.new(n + 1) { |j| i == 0 ? j : j == 0 ? i : 0 } }
      (1..m).each { |i| (1..n).each { |j|
        dp[i][j] = a[i-1] == b[j-1] ? dp[i-1][j-1] : 1 + [dp[i-1][j], dp[i][j-1], dp[i-1][j-1]].min
      }}
      dp[m][n]
    }

    MATCH_CHAPTER = -> str {
      str = str.to_s.strip
      normalized = str.downcase.gsub(/\s+/, '')

      CHAPTERS.find { |chap|
        en = chap[:english].downcase.gsub(/\s+/, '')
        chap[:code].to_s.downcase == normalized                         ||
        en == normalized                                                ||
        chap[:chinese] == str                                           ||
        chap[:acronyms].any? { |a| a.downcase == normalized }           ||
        en.start_with?(normalized)                                      ||
        chap[:acronyms].any? { |a| a.downcase.start_with?(normalized) } ||
        LEVENSHTEIN.(en, normalized) <= 2
      }
    }

    CHAPTERS = [
      { max: 50, code: :'Genesis', english: 'Genesis', chinese: '創世記', acronyms: ['創', 'Gen'] },
      { max: 40, code: :'Exodus', english: 'Exodus', chinese: '出埃及記', acronyms: ['出', 'Exo', 'Exod'] },
      { max: 27, code: :'Leviticus', english: 'Leviticus', chinese: '利未記', acronyms: ['利', 'Lev'] },
      { max: 36, code: :'Numbers', english: 'Numbers', chinese: '民數記', acronyms: ['民', 'Num'] },
      { max: 34, code: :'Deuteronomy', english: 'Deuteronomy', chinese: '申命記', acronyms: ['申', 'Deut', 'Deu'] },
      { max: 24, code: :'Joshua', english: 'Joshua', chinese: '約書亞記', acronyms: ['書', 'Josh', 'Jos'] },
      { max: 21, code: :'Judges', english: 'Judges', chinese: '士師記', acronyms: ['士', 'Judg', 'Jug'] },
      { max: 4, code: :'Ruth', english: 'Ruth', chinese: '路得記', acronyms: ['得', 'Ruth', 'Rut'] },
      { max: 31, code: :'1Samuel', english: '1 Samuel', chinese: '撒母耳記上', acronyms: ['撒上', '1Sam', '1Sa'] },
      { max: 24, code: :'2Samuel', english: '2 Samuel', chinese: '撒母耳記下', acronyms: ['撒下', '2Sam', '2Sa'] },
      { max: 22, code: :'1Kings', english: '1 Kings', chinese: '列王紀上', acronyms: ['王上', '1Kgs', '1Ki'] },
      { max: 25, code: :'2Kings', english: '2 Kings', chinese: '列王紀下', acronyms: ['王下', '2Kgs', '2Ki'] },
      { max: 29, code: :'1Chronicles', english: '1 Chronicles', chinese: '歷代志上', acronyms: ['代上', '1Chron', '1Ch'] },
      { max: 36, code: :'2Chronicles', english: '2 Chronicles', chinese: '歷代志下', acronyms: ['代下', '2Chron', '2Ch'] },
      { max: 10, code: :'Ezra', english: 'Ezra', chinese: '以斯拉記', acronyms: ['拉', 'Ezra', 'Ezr'] },
      { max: 13, code: :'Nehemiah', english: 'Nehemiah', chinese: '尼希米記', acronyms: ['尼', 'Neh'] },
      { max: 10, code: :'Esther', english: 'Esther', chinese: '以斯帖記', acronyms: ['斯', 'Est'] },
      { max: 42, code: :'Job', english: 'Job', chinese: '約伯記', acronyms: ['伯', 'Job'] },
      { max: 150, code: :'Psalm', english: 'Psalm', chinese: '詩篇', acronyms: ['詩', 'Ps', 'Psa'] },
      { max: 31, code: :'Proverbs', english: 'Proverbs', chinese: '箴言', acronyms: ['箴', 'Prov', 'Pro'] },
      { max: 12, code: :'Ecclesiastes', english: 'Ecclesiastes', chinese: '傳道書', acronyms: ['傳', 'Ecc', 'Eccl'] },
      { max: 8, code: :'SongOfSongs', english: 'Song of Songs', chinese: '雅歌', acronyms: ['歌', 'Song', 'Son'] },
      { max: 66, code: :'Isaiah', english: 'Isaiah', chinese: '以賽亞書', acronyms: ['賽', 'Isa'] },
      { max: 52, code: :'Jeremiah', english: 'Jeremiah', chinese: '耶利米書', acronyms: ['耶', 'Jer'] },
      { max: 5, code: :'Lamentations', english: 'Lamentations', chinese: '耶利米哀歌', acronyms: ['哀', 'Lam'] },
      { max: 48, code: :'Ezekiel', english: 'Ezekiel', chinese: '以西結書', acronyms: ['結', 'Ezek', 'Eze'] },
      { max: 12, code: :'Daniel', english: 'Daniel', chinese: '但以理書', acronyms: ['但', 'Dan'] },
      { max: 14, code: :'Hosea', english: 'Hosea', chinese: '何西阿書', acronyms: ['何', 'Hos'] },
      { max: 3, code: :'Joel', english: 'Joel', chinese: '約珥書', acronyms: ['珥', 'Joel', 'Joe'] },
      { max: 9, code: :'Amos', english: 'Amos', chinese: '阿摩司書', acronyms: ['摩', 'Amos'] },
      { max: 1, code: :'Obadiah', english: 'Obadiah', chinese: '俄巴底亞書', acronyms: ['俄', 'Obad', 'Oba'] },
      { max: 4, code: :'Jonah', english: 'Jonah', chinese: '約拿書', acronyms: ['拿', 'Jonah', 'Jon'] },
      { max: 7, code: :'Micah', english: 'Micah', chinese: '彌迦書', acronyms: ['彌', 'Mic'] },
      { max: 3, code: :'Nahum', english: 'Nahum', chinese: '那鴻書', acronyms: ['鴻', 'Nah'] },
      { max: 3, code: :'Habakkuk', english: 'Habakkuk', chinese: '哈巴谷書', acronyms: ['哈', 'Hab'] },
      { max: 3, code: :'Zephaniah', english: 'Zephaniah', chinese: '西番雅書', acronyms: ['番', 'Zeph', 'Zep'] },
      { max: 2, code: :'Haggai', english: 'Haggai', chinese: '哈該書', acronyms: ['該', 'Hag'] },
      { max: 14, code: :'Zechariah', english: 'Zechariah', chinese: '撒迦利亞書', acronyms: ['亞', 'Zech', 'Zec'] },
      { max: 4, code: :'Malachi', english: 'Malachi', chinese: '瑪拉基書', acronyms: ['瑪', 'Mal'] },
      { max: 28, code: :'Matthew', english: 'Matthew', chinese: '馬太福音', acronyms: ['太', 'Matt', 'Mat'] },
      { max: 16, code: :'Mark', english: 'Mark', chinese: '馬可福音', acronyms: ['可', 'Mark', 'Mak'] },
      { max: 24, code: :'Luke', english: 'Luke', chinese: '路加福音', acronyms: ['路', 'Luke', 'Luk'] },
      { max: 21, code: :'John', english: 'John', chinese: '約翰福音', acronyms: ['約', 'John', 'Jhn'] },
      { max: 28, code: :'Acts', english: 'Acts', chinese: '使徒行傳', acronyms: ['徒', 'Acts', 'Act'] },
      { max: 16, code: :'Romans', english: 'Romans', chinese: '羅馬書', acronyms: ['羅', 'Rom'] },
      { max: 16, code: :'1Corinthians', english: '1 Corinthians', chinese: '哥林多前書', acronyms: ['林前', '1Cor', '1Co'] },
      { max: 13, code: :'2Corinthians', english: '2 Corinthians', chinese: '哥林多後書', acronyms: ['林後', '2Cor', '2Co'] },
      { max: 6, code: :'Galatians', english: 'Galatians', chinese: '加拉太書', acronyms: ['加', 'Gal'] },
      { max: 6, code: :'Ephesians', english: 'Ephesians', chinese: '以弗所書', acronyms: ['弗', 'Eph'] },
      { max: 4, code: :'Philippians', english: 'Philippians', chinese: '腓立比書', acronyms: ['腓', 'Phil', 'Phl'] },
      { max: 4, code: :'Colossians', english: 'Colossians', chinese: '歌羅西書', acronyms: ['西', 'Col'] },
      { max: 5, code: :'1Thessalonians', english: '1 Thessalonians', chinese: '帖撒羅尼迦前書', acronyms: ['帖前', '1Thess', '1Ts'] },
      { max: 3, code: :'2Thessalonians', english: '2 Thessalonians', chinese: '帖撒羅尼迦後書', acronyms: ['帖後', '2Thess', '2Ts'] },
      { max: 6, code: :'1Timothy', english: '1 Timothy', chinese: '提摩太前書', acronyms: ['提前', '1Tim', '1Ti'] },
      { max: 4, code: :'2Timothy', english: '2 Timothy', chinese: '提摩太後書', acronyms: ['提後', '2Tim', '2Ti'] },
      { max: 3, code: :'Titus', english: 'Titus', chinese: '提多書', acronyms: ['多', 'Titus', 'Tit'] },
      { max: 1, code: :'Philemon', english: 'Philemon', chinese: '腓利門書', acronyms: ['門', 'Philem', 'Phm'] },
      { max: 13, code: :'Hebrews', english: 'Hebrews', chinese: '希伯來書', acronyms: ['來', 'Heb'] },
      { max: 5, code: :'James', english: 'James', chinese: '雅各書', acronyms: ['雅', 'James', 'Jas'] },
      { max: 5, code: :'1Peter', english: '1 Peter', chinese: '彼得前書', acronyms: ['彼前', '1Pet', '1Pe'] },
      { max: 3, code: :'2Peter', english: '2 Peter', chinese: '彼得後書', acronyms: ['彼後', '2Pet', '2Pe'] },
      { max: 5, code: :'1John', english: '1 John', chinese: '約翰一書', acronyms: ['約一', '1John', '1Jn'] },
      { max: 1, code: :'2John', english: '2 John', chinese: '約翰二書', acronyms: ['約二', '2John', '2Jn'] },
      { max: 1, code: :'3John', english: '3 John', chinese: '約翰三書', acronyms: ['約三', '3John', '3Jn'] },
      { max: 1, code: :'Jude', english: 'Jude', chinese: '猶大書', acronyms: ['猶', 'Jude', 'Jud'] },
      { max: 22, code: :'Revelation', english: 'Revelation', chinese: '啟示錄', acronyms: ['啟', 'Rev'] },
    ];
  end
end

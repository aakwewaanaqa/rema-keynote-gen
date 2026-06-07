# 歌詞示範

1. 用 magic comment 當作程式碼指示
2. `#!` 是設定值一定會在最前面
    1. `line=3` 表示會有三行
    2. `placeholders=<Name>,<Name>,<Name>` 表示模板佔位符的名字各自是
       注意佔位符有順序，第一個對應的就是第一行，以此類推
3. `# <Name>` 是輸出到哪一個資料夾
    1. `# <Name>` 是以上是這段
    2. `# end <Name>` 是結束這段
4. 讀取時要消除空行，那是給人看的

```txt
#! line=3
#! placeholders=kr,cn,en
# Chorus

영광의 주님
榮光中 再臨
You are Glorious

예수 영광의 주님
耶穌 榮光中 再臨
Jesus You are glorious

모든 만물이 주 위엄을 찬양하네
讓這 眾百姓 在祢愛裡 讚美歸祢
Let creation sings His majesty and mistery

승리의 주님
勝利中 再臨
You're victorious

예수 스리의 주님
耶穌 勝利中 再臨
Jesus You're victorious

모든 천사들 다시 사신 왕 찬양해
讓那 眾天使 屈膝敬拜 復活真神
With the angels sing the wonder of the risen King

# end Chorus
# Verse

주와 같은 분은 없네
世上無人 與你相比
There's no one can stand against.

전능하신 나의 주님
全能真神 主就是祢
The almighty, He who my King.

# end Verse
```

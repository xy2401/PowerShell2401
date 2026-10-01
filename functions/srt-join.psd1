@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'srt-join'
    Cases = @(
        @{
            Id = 'overlap-and-offset'
            Example = 'bilingual'
            Input = @{
                TextFiles = @(
                    @{
                        Path = 'sample.zh.srt'
                        Content = @'
1
00:00:00,000 --> 00:00:01,000
你好

2
00:00:01,200 --> 00:00:02,000
第二句

3
00:00:03,000 --> 00:00:04,000
独立字幕
'@
                    }
                    @{
                        Path = 'sample.en.srt'
                        Content = @'
1
00:00:00,000 --> 00:00:01,000
Hello

2
00:00:01,250 --> 00:00:02,050
Second line

3
00:00:05,000 --> 00:00:06,000
Independent subtitle
'@
                    }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input/sample.zh-en.srt')
                FileContains = @(
                    @{ Path = 'input/sample.zh-en.srt'; Contains = @('Hello', 'Second line', 'Independent subtitle') }
                )
            }
        }
    )
}

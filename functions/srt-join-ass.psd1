@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'srt-join-ass'
    Cases = @(
        @{
            Id = 'bilingual-ass-output'
            Example = 'bilingual-ass'
            Input = @{
                TextFiles = @(
                    @{ Path = 'sample.zh.srt'; Content = "1`n00:00:00,000 --> 00:00:01,000`n你好`n" }
                    @{ Path = 'sample.en.srt'; Content = "1`n00:00:00,000 --> 00:00:01,000`nHello`n" }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input/combined.ass.ass')
                FileContains = @(
                    @{ Path = 'input/combined.ass.ass'; Contains = @('[Script Info]', 'Hello') }
                )
            }
        }
    )
}

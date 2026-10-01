@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'srt-split'
    Cases = @(
        @{
            Id = 'two-subtitle-streams'
            Example = 'extract-subtitles'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/fixtures/media/subtitles/two-streams.mkv'; Target = 'subtitled.mkv' }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input/subtitled.01-zh.srt', 'input/subtitled.02-en.srt')
                FileContains = @(
                    @{ Path = 'input/subtitled.01-zh.srt'; Contains = @('你好') }
                    @{ Path = 'input/subtitled.02-en.srt'; Contains = @('Hello') }
                )
            }
        }
    )
}

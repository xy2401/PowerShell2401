@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'dir-tag'
    Cases = @(
        @{
            Id = 'replace-size-tag'
            Example = 'replace-last-tag'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/magika_basic/txt/many-words.txt'; Target = '层级 A/子目录/nested 3.txt' }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input/层级 A [67 Bytes]/子目录/nested 3.txt')
                Missing = @('input/层级 A')
            }
        }
    )
}

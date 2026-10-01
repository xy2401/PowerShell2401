@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'dir-info'
    Cases = @(
        @{
            Id = 'nested-extension-summary'
            Example = 'extension-summary'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/magika_basic/jpeg/magika_test.jpg'; Target = '照片 01.jpg' }
                    @{ Source = 'tests/magika_basic/txt/many-words.txt'; Target = '层级 A/子目录/nested 3.txt' }
                )
            }
            Expected = @{
                ExitCode = 0
                StdoutContains = @('Extension Summary', '.txt', 'Scan Complete')
                Exists = @('input/层级 A/子目录/nested 3.txt')
            }
        }
    )
}

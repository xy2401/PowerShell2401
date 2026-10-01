@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'hard-link'
    Cases = @(
        @{
            Id = 'mirror-files-as-links'
            Example = 'mirror-links'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/magika_basic/jpeg/magika_test.jpg'; Target = '照片 01.jpg' }
                    @{ Source = 'tests/magika_basic/txt/many-words.txt'; Target = '层级 A/子目录/nested 3.txt' }
                )
                TextFiles = @(
                    @{ Path = '无扩展名'; Content = 'pw2401 test fixture' }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input.hardlink/照片 01.jpg', 'input.hardlink/层级 A/子目录/nested 3.txt', 'input.hardlink/无扩展名')
            }
        }
    )
}

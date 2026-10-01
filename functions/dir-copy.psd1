@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'dir-copy'
    Cases = @(
        @{
            Id = 'txt-files-and-nested-directory'
            Example = 'extension-filter'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/magika_basic/txt/one-sentence.txt'; Target = '说明 10.txt' }
                    @{ Source = 'tests/magika_basic/txt/many-words.txt'; Target = '层级 A/子目录/nested 3.txt' }
                    @{ Source = 'tests/magika_basic/jpeg/magika_test.jpg'; Target = '照片 01.jpg' }
                )
                Directories = @('空目录')
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input.copy/说明 10.txt', 'input.copy/层级 A/子目录/nested 3.txt')
                Missing = @('input.copy/照片 01.jpg')
            }
        }
    )
}

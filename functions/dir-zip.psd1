@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'dir-zip'
    Cases = @(
        @{
            Id = 'known-directory-tree'
            Example = 'zip-depth'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/magika_basic/png/magika_test.png'; Target = 'book 01/cover.png' }
                )
                TextFiles = @(
                    @{ Path = 'book 01/001.txt'; Content = 'first' }
                    @{ Path = 'book 01/nested/002.txt'; Content = 'second' }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input.zip/book 01.zip')
            }
        }
    )
}

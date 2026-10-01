@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'dir-trim'
    Cases = @(
        @{
            Id = 'pad-natural-numbers'
            Example = 'pad-numbers'
            Input = @{
                TextFiles = @(
                    @{ Path = 'prefix-(1)-suffix.txt'; Content = 'one' }
                    @{ Path = 'prefix-(2)-suffix.txt'; Content = 'two' }
                    @{ Path = 'prefix-(10)-suffix.txt'; Content = 'ten' }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input/prefix-(01)-suffix.txt', 'input/prefix-(02)-suffix.txt', 'input/prefix-(10)-suffix.txt')
                Missing = @('input/prefix-(1)-suffix.txt', 'input/prefix-(2)-suffix.txt')
            }
        }
    )
}

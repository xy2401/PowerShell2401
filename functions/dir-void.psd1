@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'dir-void'
    Cases = @(
        @{
            Id = 'delete-empty-and-move-shell'
            Example = 'delete-empty-move-up'
            Input = @{
                Directories = @('empty-folder', 'outer-only/inner', 'normal/child-a', 'normal/child-b')
                TextFiles = @(
                    @{ Path = 'normal/keep.txt'; Content = 'keep' }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input/inner', 'input/normal/keep.txt')
                Missing = @('input/empty-folder', 'input/outer-only')
            }
        }
    )
}

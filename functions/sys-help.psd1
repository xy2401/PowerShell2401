@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'sys-help'
    Cases = @(
        @{
            Id = 'list-commands'
            Example = 'command-list'
            Expected = @{
                ExitCode = 0
                StdoutContains = @('dir-copy', 'ff-svt')
            }
        }
    )
}

@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'sys-status'
    Cases = @(
        @{
            Id = 'current-runtime'
            Example = 'runtime-status'
            Expected = @{
                ExitCode = 0
                StdoutContains = @('status')
            }
        }
    )
}

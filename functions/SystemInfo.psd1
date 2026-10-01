@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'SystemInfo'
    Cases = @(
        @{
            Id = 'system-summary-or-fallback'
            Example = 'system-summary'
            Expected = @{
                ExitCode = 0
                StdoutContains = @('OS', 'Version', 'CPU', 'RAM')
            }
        }
    )
}

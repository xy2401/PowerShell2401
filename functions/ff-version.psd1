@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'ff-version'
    Cases = @(
        @{
            Id = 'encoder-capabilities'
            Example = 'inspect-capabilities'
            Expected = @{
                ExitCode = 0
                StdoutContains = @('FFmpeg', 'SVT-AV1', 'NVENC')
                Exists = @('input.debug.encoders.log', 'input.debug.svt.log', 'input.debug.nv.log')
            }
        }
    )
}

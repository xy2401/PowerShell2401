@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'ff-vmaf'
    Cases = @(
        @{
            Id = 'source-and-lossy-encode'
            Example = 'compare-directories'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/fixtures/media/vmaf/source/sample.mkv'; Target = 'source/sample.mkv' }
                    @{ Source = 'tests/fixtures/media/vmaf/encoded/sample.mp4'; Target = 'encoded/sample.mp4' }
                )
            }
            Expected = @{
                ExitCode = 0
                StdoutContains = @('VMAF', 'encoded')
                ExistsMatches = @('input/VMAF_Report_*.csv')
            }
        }
    )
}

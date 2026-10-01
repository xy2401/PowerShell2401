@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'dir-unzip'
    Cases = @(
        @{
            Id = 'real-zip-sample'
            Example = 'zip-depth'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/magika_basic/zip/magika_test.zip'; Target = 'magika_test.zip' }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input.unzip/magika_test/MagikaTestDocument.html')
            }
        }
    )
}

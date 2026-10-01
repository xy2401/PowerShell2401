@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'ff-info'
    Cases = @(
        @{
            Id = 'images-and-short-video'
            Example = 'inspect-media'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/magika_basic/jpeg/magika_test.jpg'; Target = '01 横图.jpg' }
                    @{ Source = 'tests/magika_basic/png/magika_test.png'; Target = '图片[2].png' }
                    @{ Source = 'tests/fixtures/media/short-video.mkv'; Target = 'sample.mkv' }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input.info/01 横图.info.json', 'input.info/图片[2].info.json', 'input.info/sample.info.json')
                FileContains = @(
                    @{ Path = 'input.info/sample.info.json'; Contains = @('format', 'streams') }
                )
            }
        }
    )
}

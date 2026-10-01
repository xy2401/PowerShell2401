@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'ff-svt'
    Cases = @(
        @{
            Id = 'fast-images-and-video'
            Example = 'fast'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/magika_basic/jpeg/magika_test.jpg'; Target = '01 横图.jpg' }
                    @{ Source = 'tests/magika_basic/png/magika_test.png'; Target = '图片[2].png' }
                    @{ Source = 'tests/fixtures/media/short-video.mkv'; Target = 'sample.mkv' }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input.av1_svt/01 横图.avif', 'input.av1_svt/图片[2].avif', 'input.av1_svt/sample.mp4')
                Missing = @('input.av1_svt/sample.avif')
                Media = @(
                    @{ Path = 'input.av1_svt/sample.mp4'; Type = 'video'; Width = 320; Height = 240; MinDuration = 0.9 }
                )
            }
        }
    )
}

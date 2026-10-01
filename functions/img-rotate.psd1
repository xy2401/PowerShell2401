@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'img-rotate'
    Cases = @(
        @{
            Id = 'jpg-and-png'
            Example = 'rotate-90'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/magika_basic/jpeg/magika_test.jpg'; Target = '01 横图.jpg' }
                    @{ Source = 'tests/magika_basic/png/magika_test.png'; Target = '图片[2].png' }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input/01 横图.jpg', 'input/图片[2].png')
                Images = @(
                    @{ Path = 'input/01 横图.jpg'; Width = 540; Height = 960; Orientation = 1 }
                    @{ Path = 'input/图片[2].png'; Width = 540; Height = 960; Orientation = 1 }
                )
            }
        }
    )
}

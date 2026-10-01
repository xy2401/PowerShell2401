@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'ff-masonry'
    Cases = @(
        @{
            Id = 'mixed-aspect-ratios'
            Example = 'three-columns'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/magika_basic/jpeg/magika_test.jpg'; Target = '01 横图.jpg' }
                    @{ Source = 'tests/magika_basic/png/magika_test.png'; Target = '图片[2].png' }
                    @{ Source = 'tests/fixtures/media/masonry/portrait.png'; Target = '03-portrait.png' }
                    @{ Source = 'tests/fixtures/media/masonry/wide.png'; Target = '04-wide.png' }
                    @{ Source = 'tests/fixtures/media/masonry/square.png'; Target = '05-square.png' }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input.masonry/input.masonry.jpg')
            }
        }
    )
}

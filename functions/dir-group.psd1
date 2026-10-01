@{
    SchemaVersion = 1
    Kind = 'Pw2401Test'
    Function = 'dir-group'
    Cases = @(
        @{
            Id = 'image-and-video-groups'
            Example = 'group-media'
            Input = @{
                Copy = @(
                    @{ Source = 'tests/magika_basic/jpeg/magika_test.jpg'; Target = '照片 01.jpg' }
                    @{ Source = 'tests/magika_basic/png/magika_test.png'; Target = '图片[02].png' }
                )
                TextFiles = @(
                    @{ Path = '占位视频.mp4'; Content = 'extension classification fixture' }
                    @{ Path = '保留说明.txt'; Content = 'not grouped' }
                )
            }
            Expected = @{
                ExitCode = 0
                Exists = @('input/P/照片 01.jpg', 'input/P/图片[02].png', 'input/V/占位视频.mp4', 'input/保留说明.txt')
            }
        }
    )
}

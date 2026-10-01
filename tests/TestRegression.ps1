# Focused regression tests; no additional test framework is required.
param(
    [string]$WorkDir = (Split-Path $PSScriptRoot -Parent),
    [switch]$External
)

$projectRoot = Split-Path $PSScriptRoot -Parent
$runRoot = Join-Path ([IO.Path]::GetFullPath($WorkDir)) ('target/pw2401-tests/regressions/' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($runRoot)
$initialLocation = Get-Location
$ErrorActionPreference = 'Continue'
Get-ChildItem (Join-Path $projectRoot 'lib') -Filter '*.psm1' | ForEach-Object { Import-Module $_.FullName -Force }
Add-Type -AssemblyName System.Drawing
$results = [Collections.Generic.List[object]]::new()
$global:PwRegressionLog = [Collections.Generic.List[string]]::new()

function Write-LogMessage {
    param($Message, $Level, [switch]$NoPrefix, $ForegroundColor, $BackgroundColor, [switch]$NoNewline)
    $global:PwRegressionLog.Add([string]$Message)
}

function Assert-Regression {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-RegressionFailure {
    param([scriptblock]$Body, [string]$ExpectedMessage = '拷贝操作有 1 个文件失败')
    $failed = $false
    try { & $Body }
    catch {
        $failed = $true
        Assert-Regression ($_.Exception.Message.Contains($ExpectedMessage)) "Unexpected failure: $($_.Exception.Message)"
    }
    Assert-Regression $failed 'Expected the command to fail.'
}

function Set-RegressionContext {
    param([string]$Name)
    $inputPath = Join-Path $runRoot "$Name/input"
    [void][IO.Directory]::CreateDirectory($inputPath)
    Set-Location -LiteralPath $inputPath
    $global:GlobalConfig = Get-GlobalConfig -ProjectRoot $projectRoot
    return $inputPath
}

function Invoke-RegressionCase {
    param([string]$Name, [scriptblock]$Body)
    $global:PwRegressionLog.Clear()
    try {
        & $Body
        $results.Add([pscustomobject]@{ Name = $Name; Status = 'Pass'; Message = '' })
    }
    catch {
        $results.Add([pscustomobject]@{ Name = $Name; Status = 'Fail'; Message = ($_ | Out-String).Trim() })
    }
    [IO.File]::WriteAllLines((Join-Path $runRoot "$Name.log"), $global:PwRegressionLog)
}

function New-OrientationImage {
    param([string]$Path, [int]$Orientation)
    $bitmap = [Drawing.Bitmap]::new(60, 40)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $memory = [IO.MemoryStream]::new()
    try {
        $graphics.FillRectangle([Drawing.Brushes]::Red, 0, 0, 30, 20)
        $graphics.FillRectangle([Drawing.Brushes]::Lime, 30, 0, 30, 20)
        $graphics.FillRectangle([Drawing.Brushes]::Blue, 0, 20, 30, 20)
        $graphics.FillRectangle([Drawing.Brushes]::Yellow, 30, 20, 30, 20)
        $bitmap.Save($memory, [Drawing.Imaging.ImageFormat]::Jpeg)
        $jpeg = $memory.ToArray()
        # JPEG APP1 containing a little-endian TIFF IFD with EXIF Orientation.
        [byte[]]$exif = @(255,225,0,34,69,120,105,102,0,0,73,73,42,0,8,0,0,0,
            1,0,18,1,3,0,1,0,0,0,$Orientation,0,0,0,0,0,0,0)
        [IO.File]::WriteAllBytes($Path, [byte[]](@($jpeg[0..1]) + $exif + @($jpeg[2..($jpeg.Length - 1)])))
    }
    finally {
        $memory.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Get-QuadrantColors {
    param([Drawing.Bitmap]$Image)
    $colors = foreach ($point in @(@(1,1), @(3,1), @(1,3), @(3,3))) {
        $color = $Image.GetPixel([int]($Image.Width * $point[0] / 4), [int]($Image.Height * $point[1] / 4))
        if ($color.R -gt 170 -and $color.G -gt 170) { 'Y' }
        elseif ($color.R -gt $color.G -and $color.R -gt $color.B) { 'R' }
        elseif ($color.G -gt $color.B) { 'G' }
        else { 'B' }
    }
    return $colors -join ''
}

try {
    foreach ($preference in @('Continue', 'Stop')) {
        Invoke-RegressionCase "copy-failure-$preference" {
            $ErrorActionPreference = $preference
            $inputPath = Set-RegressionContext "copy-failure-$preference"
            $source = Join-Path $inputPath '保留[1].txt'
            $destination = "$inputPath.copy"
            [void][IO.Directory]::CreateDirectory($destination)
            $target = Join-Path $destination '保留[1].txt'
            [IO.File]::WriteAllText($source, 'source-content')
            [IO.File]::WriteAllText($target, 'existing-target')
            # Inject a cmdlet-style nonterminating error; the command must opt into Stop.
            function Copy-Item {
                [CmdletBinding()]
                param($LiteralPath, $Destination)
                Write-Error 'Injected copy failure'
            }
            Assert-RegressionFailure { & (Join-Path $projectRoot 'functions/dir-copy.ps1') -DeleteOriginal }
            Assert-Regression ([IO.File]::ReadAllText($source) -eq 'source-content') 'Source was changed after failed copy.'
            Assert-Regression ([IO.File]::ReadAllText($target) -eq 'existing-target') 'Existing target was changed after failed copy.'
            Assert-Regression (@(Get-ChildItem -LiteralPath $destination -Force -Filter '.pw2401-*.tmp').Count -eq 0) 'Temporary copy leaked.'
        }
    }

    Invoke-RegressionCase 'copy-truncated-output' {
        $inputPath = Set-RegressionContext 'copy-truncated-output'
        $source = Join-Path $inputPath 'file.txt'
        [void][IO.Directory]::CreateDirectory("$inputPath.copy")
        $target = Join-Path "$inputPath.copy" 'file.txt'
        [IO.File]::WriteAllText($source, 'source-content')
        [IO.File]::WriteAllText($target, 'existing-target')
        function Copy-Item {
            [CmdletBinding()]
            param($LiteralPath, $Destination)
            [IO.File]::WriteAllText($Destination, 'short')
        }
        Assert-RegressionFailure { & (Join-Path $projectRoot 'functions/dir-copy.ps1') -DeleteOriginal }
        Assert-Regression ([IO.File]::ReadAllText($source) -eq 'source-content') 'Source lost after truncated copy.'
        Assert-Regression ([IO.File]::ReadAllText($target) -eq 'existing-target') 'Truncated copy replaced the target.'
        Assert-Regression (@(Get-ChildItem -LiteralPath "$inputPath.copy" -Force -Filter '.pw2401-*.tmp').Count -eq 0) 'Truncated temporary copy leaked.'
    }

    Invoke-RegressionCase 'copy-replace-and-delete' {
        $inputPath = Set-RegressionContext 'copy-replace-and-delete'
        $source = Join-Path $inputPath '保留[1].txt'
        [void][IO.Directory]::CreateDirectory("$inputPath.copy")
        $target = Join-Path "$inputPath.copy" '保留[1].txt'
        [IO.File]::WriteAllText($source, 'new-content')
        [IO.File]::WriteAllText($target, 'old-content')
        & (Join-Path $projectRoot 'functions/dir-copy.ps1') -DeleteOriginal
        Assert-Regression (-not [IO.File]::Exists($source)) 'Source was not removed after successful copy.'
        Assert-Regression ([IO.File]::ReadAllText($target) -eq 'new-content') 'Replacement content is incorrect.'
    }

    Invoke-RegressionCase 'copy-locked-target' {
        $inputPath = Set-RegressionContext 'copy-locked-target'
        $source = Join-Path $inputPath 'file.txt'
        [void][IO.Directory]::CreateDirectory("$inputPath.copy")
        $target = Join-Path "$inputPath.copy" 'file.txt'
        [IO.File]::WriteAllText($source, 'source-content')
        [IO.File]::WriteAllText($target, 'existing-target')
        $lock = [IO.File]::Open($target, 'Open', 'ReadWrite', 'None')
        try { Assert-RegressionFailure { & (Join-Path $projectRoot 'functions/dir-copy.ps1') -DeleteOriginal } }
        finally { $lock.Dispose() }
        Assert-Regression ([IO.File]::ReadAllText($source) -eq 'source-content') 'Source lost after replacement failed.'
        Assert-Regression ([IO.File]::ReadAllText($target) -eq 'existing-target') 'Locked target was modified.'
        Assert-Regression (@(Get-ChildItem -LiteralPath "$inputPath.copy" -Force -Filter '.pw2401-*.tmp').Count -eq 0) 'Temporary copy leaked.'
    }

    $expectedCorners = @{ 2='GRYB'; 3='YBGR'; 4='BYRG'; 5='RBGY'; 6='BRYG'; 7='YGBR'; 8='GYRB' }
    foreach ($orientation in 2..8) {
        Invoke-RegressionCase "exif-$orientation" {
            $inputPath = Set-RegressionContext "exif-$orientation"
            $path = Join-Path $inputPath 'orientation.jpg'
            New-OrientationImage -Path $path -Orientation $orientation
            & (Join-Path $projectRoot 'functions/img-rotate.ps1') -SyncPixelsToExif
            $image = [Drawing.Bitmap]::new($path)
            try {
                $expectedWidth = if ($orientation -ge 5) { 40 } else { 60 }
                $expectedHeight = if ($orientation -ge 5) { 60 } else { 40 }
                Assert-Regression ($image.Width -eq $expectedWidth -and $image.Height -eq $expectedHeight) 'Incorrect rotated dimensions.'
                Assert-Regression ((Get-QuadrantColors $image) -eq $expectedCorners[$orientation]) "Incorrect pixels for EXIF $orientation."
                $tag = if ($image.PropertyIdList -contains 274) { [BitConverter]::ToInt16($image.GetPropertyItem(274).Value, 0) } else { 1 }
                Assert-Regression ($tag -eq 1) 'Orientation was not normalized.'
            }
            finally { $image.Dispose() }
            $exclusive = [IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
            $exclusive.Dispose()
        }
    }

    Invoke-RegressionCase 'image-locked-target' {
        $inputPath = Set-RegressionContext 'image-locked-target'
        $path = Join-Path $inputPath 'locked.jpg'
        New-OrientationImage -Path $path -Orientation 6
        $before = (Get-FileHash -LiteralPath $path).Hash
        $lock = [IO.File]::Open($path, 'Open', 'Read', 'Read')
        try { Assert-RegressionFailure { & (Join-Path $projectRoot 'functions/img-rotate.ps1') -SyncPixelsToExif } -ExpectedMessage '1 张图片处理失败' }
        finally { $lock.Dispose() }
        Assert-Regression ((Get-FileHash -LiteralPath $path).Hash -eq $before) 'Image changed after failed replacement.'
        Assert-Regression (@(Get-ChildItem -LiteralPath $inputPath -Force -Filter '.pw2401-*.tmp').Count -eq 0) 'Temporary image leaked.'
    }

    Invoke-RegressionCase 'file-types-and-directory-summary' {
        $inputPath = Set-RegressionContext 'file-types-and-directory-summary'
        $map = Get-FileTypeMap
        foreach ($extension in @('ts', 'sub', '3gpp')) {
            Assert-Regression ((Get-FileType "sample.$extension") -eq $map[$extension]) "Inconsistent classification: $extension"
        }
        Assert-Regression ((Get-FileType 'sample.TS') -eq 'video') 'First-category precedence changed.'
        Assert-Regression ((Get-FileType 'no-extension') -eq 'unknown') 'Extensionless file was classified.'
        Assert-Regression ((Get-FileType 'sample.unlisted') -eq 'unknown') 'Unknown extension was classified.'
        [IO.File]::WriteAllText((Join-Path $inputPath 'movie.ts'), '1234')
        [void][IO.Directory]::CreateDirectory((Join-Path $inputPath 'nested'))
        [IO.File]::WriteAllText((Join-Path $inputPath 'nested/note.txt'), 'abc')
        [void][IO.Directory]::CreateDirectory((Join-Path $inputPath '.excluded'))
        [IO.File]::WriteAllText((Join-Path $inputPath '.excluded/ignored.ts'), 'ignored')
        & (Join-Path $projectRoot 'functions/dir-info.ps1') -Csv -ExtSummary
        $row = Import-Csv -LiteralPath "$inputPath.csv"
        Assert-Regression ($row.Files_Total -eq 2 -and $row.Folders -eq 1 -and $row.Sub_Files_Total -eq 1 -and $row.Size_Total -eq 7) 'Directory totals are incorrect.'
        Assert-Regression ($row.video_Cnt -eq 1 -and $row.text_Cnt -eq 1) 'CSV classification is incorrect.'
        $global:GlobalConfig.extensions = [pscustomobject]@{ custom = @('ts') }
        Assert-Regression ((Get-FileType 'sample.ts') -eq 'custom') 'Cached classification did not follow new configuration.'
    }

    Invoke-RegressionCase 'media-unknown-duration' {
        # Missing durations and short clips must not be classified as still images.
        $module = Get-Module FFmpeg
        & $module {
            function ffprobe {
                $global:LASTEXITCODE = 0
                '{"streams":[{"codec_type":"video","width":320,"height":240}],"format":{"format_name":"matroska,webm"}}'
            }
            $info = Get-MediaInfo -Path 'unknown.mkv'
            if ($info.Type -ne 'video' -or $info.DurationKnown) { throw 'Unknown duration was treated as an image.' }
        }
        & $module {
            function ffprobe {
                $global:LASTEXITCODE = 0
                '{"streams":[{"codec_type":"video","width":320,"height":240,"duration":"0.04"}],"format":{"format_name":"mov,mp4"}}'
            }
            $info = Get-MediaInfo -Path 'short.mp4'
            if ($info.Type -ne 'video' -or -not $info.DurationKnown) { throw 'Short video was treated as an image.' }
        }
        & $module {
            function ffprobe {
                $global:LASTEXITCODE = 1
                '{"streams":[{"codec_type":"video","width":320,"height":240}],"format":{"duration":"1"}}'
            }
            $info = Get-MediaInfo -Path 'failed.mp4'
            if ($info.Type -ne 'unknown' -or $info.HasVideo) { throw 'Failed ffprobe output was accepted.' }
        }
    }

    if ($External -and (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
        Invoke-RegressionCase 'media-real-fixtures' {
            $inputPath = Set-RegressionContext 'media-real-fixtures'
            $video = Get-MediaInfo -Path (Join-Path $projectRoot 'tests/fixtures/media/short-video.mkv')
            Assert-Regression ($video.Type -eq 'video' -and $video.DurationKnown -and [Math]::Abs($video.Duration - 1) -lt 0.01) 'MKV container duration was not used.'
            foreach ($relativePath in @('tests/magika_basic/jpeg/magika_test.jpg', 'tests/magika_basic/png/magika_test.png')) {
                $image = Get-MediaInfo -Path (Join-Path $projectRoot $relativePath)
                Assert-Regression ($image.Type -eq 'image' -and $image.Width -gt 0 -and $image.Height -gt 0) 'Still image was not identified.'
            }
            $invalidPath = Join-Path $inputPath 'invalid.mp4'
            [IO.File]::WriteAllText($invalidPath, 'not-media')
            Assert-Regression ((Get-MediaInfo -Path $invalidPath).Type -eq 'unknown') 'Invalid media was accepted.'
        }
    }
    else {
        $results.Add([pscustomobject]@{ Name = 'media-real-fixtures'; Status = 'Skip'; Message = 'Requires -External and ffprobe.' })
    }
}
finally { Set-Location -LiteralPath $initialLocation.Path }

$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runRoot 'regression-report.json') -Encoding utf8
$failed = @($results | Where-Object Status -EQ 'Fail')
$passed = @($results | Where-Object Status -EQ 'Pass')
$skipped = @($results | Where-Object Status -EQ 'Skip')
Write-Host "Regression tests: Pass $($passed.Count), Fail $($failed.Count), Skip $($skipped.Count). Report: $runRoot"
foreach ($failure in $failed) { Write-Host "$($failure.Name): $($failure.Message)" -ForegroundColor Red }
if ($failed.Count -gt 0) { exit 1 }

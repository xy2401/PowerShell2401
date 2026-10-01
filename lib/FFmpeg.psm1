<#
.SYNOPSIS
    使用 ffprobe 获取媒体文件的详细信息。

.DESCRIPTION
    该函数调用一次 ffprobe，获取视频流的编码类型、宽度、高度和时长。
    返回一个包含这些属性的对象。
#>
function Get-MediaInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    # 默认值
    $info = [PSCustomObject]@{
        Path      = $Path
        Type      = "unknown"
        Width     = 0
        Height    = 0
        Duration  = 0.0
        DurationKnown = $false
        HasVideo  = $false
    }

    try {
        $probe = & ffprobe -v error -select_streams v:0 -show_entries stream=codec_type,width,height,duration,nb_frames:format=format_name,duration -of json $Path 2>$null
        if ($LASTEXITCODE -ne 0) { return $info }
        $data = ($probe -join "`n") | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Verbose "无法探测媒体 '$Path': $_"
        return $info
    }

    $stream = @($data.streams | Where-Object codec_type -EQ 'video') | Select-Object -First 1
    if ($null -eq $stream) { return $info }
    $info.HasVideo = $true
    $info.Type = 'video'
    $info.Width = [int]$stream.width
    $info.Height = [int]$stream.height

    # MKV 等容器可能只有 format.duration；未知时长不代表静态图片。
    foreach ($candidate in @($stream.duration, $data.format.duration)) {
        $duration = 0.0
        if ([double]::TryParse([string]$candidate, [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$duration) -and
            [double]::IsFinite($duration) -and $duration -gt 0) {
            $info.Duration = $duration
            $info.DurationKnown = $true
            break
        }
    }

    $formats = @(([string]$data.format.format_name) -split ',')
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $stillFormat = @($formats | Where-Object { $_ -match '^(image2|image2pipe|\w+_pipe|ico|jpegxl)$' }).Count -gt 0
    $singleHeifFrame = $extension -in @('.avif', '.heic', '.heif') -and $stream.nb_frames -eq '1'
    if ($stillFormat -or $singleHeifFrame) { $info.Type = 'image' }

    return $info
}

Export-ModuleMember -Function Get-MediaInfo

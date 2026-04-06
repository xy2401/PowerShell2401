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

    # 一次性获取 codec_type, width, height, duration
    # 使用 CSV 格式输出，方便解析
    $probe = ffprobe -v error -select_streams v:0 -show_entries stream=codec_type,width,height,duration -of csv=p=0 "$Path" 2>$null

    # 默认值
    $info = [PSCustomObject]@{
        Path      = $Path
        Type      = "unknown"
        Width     = 0
        Height    = 0
        Duration  = 0.0
        HasVideo  = $false
    }

    if (-not [string]::IsNullOrWhiteSpace($probe)) {
        # 解析结果 (例如: video,1920,1080,120.5)
        $parts = $probe.Split(',')
        
        $info.Type = $parts[0].Trim()
        $info.HasVideo = ($info.Type -eq "video")

        if ($parts.Count -ge 3) {
            $info.Width  = [int]$parts[1]
            $info.Height = [int]$parts[2]
        }
        
        if ($parts.Count -ge 4 -and $parts[3] -ne "N/A") {
            $info.Duration = [float]$parts[3]
        }
    }

    # 逻辑判定：如果是视频流但时长极短或无时长，判定为图片
    if ($info.Type -eq "video") {
        if ($info.Duration -lt 0.1) {
            $info.Type = "image"
        } else {
            $info.Type = "video"
        }
    }

    return $info
}

Export-ModuleMember -Function Get-MediaInfo

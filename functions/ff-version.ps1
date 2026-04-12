<#
.SYNOPSIS
    查看并记录 FFmpeg 及 SVT-AV1 的版本信息。

.DESCRIPTION
    该脚本会检测系统中配置的 FFmpeg 执行程序及其 SVT-AV1 编码器的详细版本。
    通过执行一次极小的模拟编码任务来诱导 SVT 输出其内部版本号。
    包含编码器列表以及 SVT/NVENC 的探测信息，并支持输出到独立日志。
#>
param()

function Get-FfmpegVersionSummary {
    param([string]$Exe)
    try {
        $realPath = (Get-Command $Exe -ErrorAction Stop).Source
        Write-LogMessage -Message "FFmpeg 所在位置: $realPath" -Level Info
        
        $versionSummary = & $Exe -version | Select-Object -First 1
        Write-LogMessage -Message "FFmpeg 摘要: $versionSummary" -Level Success
    }
    catch {
        Write-LogMessage -Message "无法执行或找到 $Exe，请检查它是否位于环境变量 PATH 中或相关配置是否正确。" -Level Error
        throw
    }
}

function Export-FfmpegEncoders {
    param([string]$Exe)
    Write-LogMessage -Message "正在获取所有支持的 FFmpeg 编码器列表..." -Level Info
    try {
        $encoders = & $Exe -hide_banner -encoders
        
        $encodersLogPath = "ff-version.encoders.log"
        if ($null -ne $global:GlobalConfig.runtime.LogFilePath) {
            $encodersLogPath = $global:GlobalConfig.runtime.LogFilePath -replace '\.[^.]+$', '.encoders.log'
        }
        $encoders | Out-File -LiteralPath $encodersLogPath -Encoding utf8
        Write-LogMessage -Message "详细编码器列表已保存至: $encodersLogPath" -Level Info
    }
    catch {
        Write-LogMessage -Message "获取编码器列表失败: $_" -Level Error
    }
}

function Probe-SvtAv1Version {
    param([string]$Exe, [string]$TempDir, [string]$TempFileName)
    Write-LogMessage -Message "正在探测 SVT-AV1 编码器内部版本 (模拟编码中)..." -Level Info
    $tempOutput = Join-Path $TempDir $TempFileName

    try {
        $svtProbe = & $Exe -hide_banner -f lavfi -i "color=c=black:s=256x256:d=1" -c:v libsvtav1 -preset 10 -frames:v 1 -f avif -y $tempOutput 2>&1
        
        $svtLogPath = "ff-version.svt.log"
        if ($null -ne $global:GlobalConfig.runtime.LogFilePath) {
            $svtLogPath = $global:GlobalConfig.runtime.LogFilePath -replace '\.[^.]+$', '.svt.log'
        }
        $svtProbe | Out-File -LiteralPath $svtLogPath -Encoding utf8
        Write-LogMessage -Message "详细日志已保存至: $svtLogPath" -Level Info
        
        $svtVersionLine = $svtProbe | Where-Object { $_ -match "SVT \[version\]|SVT-AV1 Encoder Lib" } | ForEach-Object { $_.ToString().Trim() } | Select-Object -Unique | Select-Object -First 1
        if ($svtVersionLine) {
            Write-LogMessage -Message "SVT-AV1: $svtVersionLine" -Level Success
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempOutput) { Remove-Item -LiteralPath $tempOutput -Force -ErrorAction SilentlyContinue }
    }
}

function Probe-NvencInfo {
    param([string]$Exe, [string]$TempDir, [string]$TempFileName)
    Write-LogMessage -Message "正在探测 NVIDIA NVENC 编码器信息 (模拟编码中)..." -Level Info
    $nvOutput = Join-Path $TempDir ($TempFileName + ".nv.mp4")

    try {
        $nvProbe = & $Exe -hide_banner -f lavfi -i "color=c=black:s=256x256:d=1" -c:v av1_nvenc -frames:v 1 -f mp4 -y $nvOutput 2>&1
        
        $nvLogPath = "ff-version.nv.log"
        if ($null -ne $global:GlobalConfig.runtime.LogFilePath) {
            $nvLogPath = $global:GlobalConfig.runtime.LogFilePath -replace '\.[^.]+$', '.nv.log'
        }
        $nvProbe | Out-File -LiteralPath $nvLogPath -Encoding utf8
        Write-LogMessage -Message "详细日志已保存至: $nvLogPath" -Level Info
        
        $nvInfo = $nvProbe | Where-Object { $_ -match "NVENC|driver|Nvidia" } | ForEach-Object { $_.ToString().Trim() } | Select-Object -Unique | Select-Object -First 3
        
        if ($nvInfo) {
            foreach ($line in $nvInfo) { Write-LogMessage -Message "NVENC: $line" -Level Success }
        } else {
            Write-LogMessage -Message "未探测到 NVENC 信息，请确保显卡驱动已安装且支持 AV1 编码。" -Level Warning
        }
    }
    finally {
        if (Test-Path -LiteralPath $nvOutput) { Remove-Item -LiteralPath $nvOutput -Force -ErrorAction SilentlyContinue }
    }
}

function Start-VersionCheck {
    $exe = "ffmpeg"
    if ($null -ne $dirConf -and -not [string]::IsNullOrWhiteSpace($dirConf.ffmpegSvtExe)) {
        $exe = $dirConf.ffmpegSvtExe
    }

    Write-LogMessage -Message "正在检测 FFmpeg 及相关编码器版本信息 (执行程序: $exe)..." -Level Info

    try {
        Get-FfmpegVersionSummary -Exe $exe
    } catch {
        return
    }

    Export-FfmpegEncoders -Exe $exe

    $tempDir = [System.IO.Path]::GetTempPath()
    $tempFileName = [System.Guid]::NewGuid().ToString() + ".avif"

    try {
        Probe-SvtAv1Version -Exe $exe -TempDir $tempDir -TempFileName $tempFileName
    } catch {
        Write-LogMessage -Message "SVT-AV1 探测任务异常: $($_.Exception.Message)" -Level Error
    }

    try {
        Probe-NvencInfo -Exe $exe -TempDir $tempDir -TempFileName $tempFileName
    } catch {
        Write-LogMessage -Message "NVENC 探测任务异常: $($_.Exception.Message)" -Level Error
    }
}

# -----------------
# 脚本核心执行入口
# -----------------
Start-VersionCheck

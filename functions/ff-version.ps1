<#
.SYNOPSIS
    查看并记录 FFmpeg 及 SVT-AV1 的版本信息。

.DESCRIPTION
    该脚本会检测系统中配置的 FFmpeg 执行程序及其 SVT-AV1 编码器的详细版本。
    通过执行一次极小的模拟编码任务来诱导 SVT 输出其内部版本号。
#>
param()

# 1. 确定 ffmpeg 执行程序路径
$exe = "ffmpeg"
if ($null -ne $dirConf -and -not [string]::IsNullOrWhiteSpace($dirConf.ffmpegSvtExe)) {
    $exe = $dirConf.ffmpegSvtExe
}

Write-LogMessage -Message "正在检测 FFmpeg 及 SVT-AV1 版本信息 (执行程序: $exe)..." -Level Info

# 2. 获取 FFmpeg 基础版本
try {
    $versionSummary = & $exe -version | Select-Object -First 1
    Write-LogMessage -Message "FFmpeg 摘要: $versionSummary" -Level Success
}
catch {
    Write-LogMessage -Message "无法执行 $exe，请检查配置。" -Level Error; return
}

# 2.5 列出所有编码器
Write-LogMessage -Message "正在获取所有支持的 FFmpeg 编码器列表..." -Level Info
try {
    $encoders = & $exe -hide_banner -encoders
    
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

# 3. 构造极小任务探测 SVT-AV1 版本
$tempDir = [System.IO.Path]::GetTempPath()
$tempFileName = [System.Guid]::NewGuid().ToString() + ".avif"
$tempOutput = Join-Path $tempDir $tempFileName
try {
    # --- 探测 SVT-AV1 ---
    Write-LogMessage -Message "正在探测 SVT-AV1 编码器内部版本 (模拟编码中)..." -Level Info
    $svtProbe = & $exe -hide_banner -f lavfi -i "color=c=black:s=256x256:d=1" -c:v libsvtav1 -preset 10 -frames:v 1 -f avif -y $tempOutput 2>&1
    
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

    # --- 探测 NVENC ---
    Write-LogMessage -Message "正在探测 NVIDIA NVENC 编码器信息 (模拟编码中)..." -Level Info
    $nvOutput = Join-Path $tempDir ($tempFileName + ".nv.mp4")
    $nvProbe = & $exe -hide_banner -f lavfi -i "color=c=black:s=256x256:d=1" -c:v av1_nvenc -frames:v 1 -f mp4 -y $nvOutput 2>&1
    
    $nvLogPath = "ff-version.nv.log"
    if ($null -ne $global:GlobalConfig.runtime.LogFilePath) {
        $nvLogPath = $global:GlobalConfig.runtime.LogFilePath -replace '\.[^.]+$', '.nv.log'
    }
    $nvProbe | Out-File -LiteralPath $nvLogPath -Encoding utf8
    Write-LogMessage -Message "详细日志已保存至: $nvLogPath" -Level Info
    
    # NVENC 通常会输出驱动版本 (Driver version) 或初始化信息
    $nvInfo = $nvProbe | Where-Object { $_ -match "NVENC|driver|Nvidia" } | ForEach-Object { $_.ToString().Trim() } | Select-Object -Unique | Select-Object -First 3
    
    if ($nvInfo) {
        foreach ($line in $nvInfo) { Write-LogMessage -Message "NVENC: $line" -Level Success }
    } else {
        Write-LogMessage -Message "未探测到 NVENC 信息，请确保显卡驱动已安装且支持 AV1 编码。" -Level Warning
    }

    # 清理 NV 临时文件
    if (Test-Path -LiteralPath $nvOutput) { Remove-Item -LiteralPath $nvOutput -Force }

    # 如果开启了 Debug，记录完整输出
    if ($dirArgs.debug) {
        Write-LogMessage -Message "--- 完整探测日志已记录 ---" -Level Info
        $svtProbe | ForEach-Object { Write-LogMessage -Message $_.ToString().Trim() -Level Info }
    }
}
catch {
    Write-LogMessage -Message "SVT-AV1 探测任务执行失败: $($_.Exception.Message)" -Level Error
}
finally {
    # 清理临时文件
    if (Test-Path -LiteralPath $tempOutput) { Remove-Item -LiteralPath $tempOutput -Force }
}

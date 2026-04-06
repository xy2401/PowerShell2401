<#
.SYNOPSIS
    使用 FFmpeg 实现瀑布流图片拼接。
    将多张图片拼接成符合指定宽度和列数的瀑布流长图。

.DESCRIPTION
    该脚本扫描当前工作目录下的所有图片，根据图片原始比例计算缩放后的高度，
    并动态生成瀑布流布局。可以通过命令行参数自定义输出的列数、画布宽度、间隙大小、背景颜色等。

.EXAMPLE
    .\Build.ps1
    使用默认参数运行脚本，将会把当前目录下的图片拼成列数为 2、宽度 1024、白色背景的瀑布流。

.EXAMPLE
    .\Build.ps1 -ColumnCount 3 -CanvasWidth 1920 -BackgroundColor "black" -Gap 10
    将图片拼成 3 列，总宽度 1920 像素，背景设为黑色，图片间距 10 像素。

.EXAMPLE
    .\Build.ps1 -CropSize "Auto"
    开启统一裁剪模式，自动计算文件夹内图片尺寸的众数作为裁剪比例，让图片堆叠更加整齐。

.EXAMPLE
    .\Build.ps1 -ShowFileName $false
    隐藏图片上方默认绘制的文件名称条。
#>

[CmdletBinding()]
param (
    [Parameter(HelpMessage = "画布的整体宽度（像素）。默认 3000")]
    [int]$CanvasWidth = 3000,

    [Parameter(HelpMessage = "瀑布流的列数。默认 5。")]
    [int]$ColumnCount = 5,

    [Parameter(HelpMessage = "容差系数，用于决定把图片放在哪一列。默认 2。")]
    [double]$Tolerance = 2,

    [Parameter(HelpMessage = "图片之间的间隙大小（像素）。默认 0。")]
    [int]$Gap = 0,

    [Parameter(HelpMessage = "画布的背景颜色（支持英文颜色词或十六进制如 0xFFFFFF）。默认 'white'。")]
    [string]$BackgroundColor = "white",

    [Parameter(HelpMessage = "是否在图片上方显示文件名。默认 `$true。")]
    [bool]$ShowFileName = $false,

    [Parameter(HelpMessage = "显示文件名时的字体大小。默认 20。")]
    [int]$FontSize = 20,

    [Parameter(HelpMessage = "文件名排序方式。'Smart'（智能自然数字排序，默认）或 'Name'（普通按字母顺序）。")]
    [ValidateSet("Smart", "Name")]
    [string]$Sort = "Smart",

    [Parameter(HelpMessage = "处理路径的深度。默认 0 即仅当前目录，1 表示包含所有一级子目录，以此类推。")]
    [int]$Depth = 0,

    [Parameter(HelpMessage = "统一裁剪尺寸格式 '宽x高' (如 '1920x1080')。设置为 'Auto' 时自动计算尺寸众数，不设置或为空则关闭统一裁剪（保留原始比例）。")]
    [string]$CropSize = ""
)

# =======================================================
# 辅助函数定义区
# =======================================================

# --- 1. 获取媒体信息 ---
function Get-MediaInfo {
    param ([string]$FilePath)
    
    $ffprobeArgs = @(
        "-v", "error", 
        "-select_streams", "v:0", 
        "-show_entries", "stream=codec_type,width,height:format=duration", 
        "-of", "json", 
        $FilePath
    )
    
    $jsonOutput = & ffprobe @ffprobeArgs 2>$null | ConvertFrom-Json
    
    if ($jsonOutput.streams -and $jsonOutput.streams[0].codec_type -eq "video") {
        $width = $jsonOutput.streams[0].width
        $height = $jsonOutput.streams[0].height
        $duration = $jsonOutput.format.duration
        
        # 判定为图片：时长极短或缺失
        if ([string]::IsNullOrWhiteSpace($duration) -or $duration -eq "N/A" -or [float]$duration -lt 0.1) {
            return [PSCustomObject]@{
                Width  = [int]$width
                Height = [int]$height
            }
        }
    }
    return $null
}

# --- 2. 计算统一裁剪尺寸信息 ---
function Get-CropInfo {
    param (
        [Parameter(Mandatory = $true)][array]$ValidFiles,
        [string]$CropSize
    )

    $Result = [PSCustomObject]@{
        IsUniformMode = $false
        TargetRatioW  = 0
        TargetRatioH  = 0
    }

    if ([string]::IsNullOrWhiteSpace($CropSize)) {
        return $Result
    }

    $Result.IsUniformMode = $true

    if ($CropSize -eq "Auto") {
        Write-Host "`n--- 分析图片尺寸众数 ---" -ForegroundColor Cyan
        $SizeGroups = $ValidFiles | Group-Object -Property { "$($_.Width)x$($_.Height)" } | Sort-Object Count -Descending
        $ModeSize = $SizeGroups[0].Name
        Write-Host "得出最常见尺寸 (众数): $ModeSize (占比 $($SizeGroups[0].Count) / $($ValidFiles.Count))" -ForegroundColor Yellow
        
        $ModeParts = $ModeSize.Split('x')
        $Result.TargetRatioW = [int]$ModeParts[0]
        $Result.TargetRatioH = [int]$ModeParts[1]
    }
    elseif ($CropSize -match "^\d+x\d+$") {
        $ModeParts = $CropSize.Split('x')
        $Result.TargetRatioW = [int]$ModeParts[0]
        $Result.TargetRatioH = [int]$ModeParts[1]
        Write-Host "`n指定强制裁剪比例尺寸: $($Result.TargetRatioW)x$($Result.TargetRatioH)" -ForegroundColor Yellow
    }
    else {
        Write-Warning "CropSize 参数格式错误，应类似 '1920x1080' 或 'Auto'。功能已关闭，回退为原生比例瀑布流。"
        $Result.IsUniformMode = $false
    }

    return $Result
}

# --- 3. 计算瀑布流布局与滤镜参数 (基于上下文对象) ---
function Get-MasonryLayout {
    param (
        [Parameter(Mandatory = $true)][array]$ValidFiles,
        [Parameter(Mandatory = $true)][PSCustomObject]$Config
    )

    $ColWidth = [int]($Config.CanvasWidth / $Config.ColumnCount)
    $ColHeights = New-Object int[] $Config.ColumnCount
    $ColFileCounts = New-Object int[] $Config.ColumnCount
    $ColFileLists = [System.Collections.ArrayList[]]::new($Config.ColumnCount)
    for ($j = 0; $j -lt $Config.ColumnCount; $j++) { $ColFileLists[$j] = [System.Collections.ArrayList]::new() }

    $FfmpegInputArgs = @()
    $Filters = @()
    $Layouts = @()
    $CurrentCol = 0

    for ($i = 0; $i -lt $ValidFiles.Count; $i++) {
        $FileObj = $ValidFiles[$i]
        $File = $FileObj.File
        $W = $FileObj.Width
        $H = $FileObj.Height

        if ($W -le 0 -or $H -le 0) { continue }

        if ($Config.IsUniformMode -and $Config.TargetRatioW -gt 0) {
            $ScaledH = [int]($ColWidth * $Config.TargetRatioH / $Config.TargetRatioW)
            $ImageFilter = "scale=${ColWidth}:${ScaledH}:force_original_aspect_ratio=increase,crop=${ColWidth}:${ScaledH}"
        }
        else {
            $ScaledH = [int]($ColWidth * $H / $W)
            $ImageFilter = "scale=${ColWidth}:-1"
        }

        $MinH = $ColHeights[0]; $ShortestIdx = 0
        for ($j = 1; $j -lt $Config.ColumnCount; $j++) {
            if ($ColHeights[$j] -lt $MinH) { $MinH = $ColHeights[$j]; $ShortestIdx = $j }
        }

        $TargetCol = if (($ColHeights[$CurrentCol] - $MinH) -gt ($ScaledH * $Config.Tolerance)) { $ShortestIdx } else { $CurrentCol }
        $PosX = $TargetCol * ($ColWidth + $Config.Gap)
        $PosY = $ColHeights[$TargetCol]

        if ($Config.ShowFileName) {
            $EscapedName = $File.Name.Replace(":", "\\:").Replace("'", "").Replace("[", "\[").Replace("]", "\]")
            $ImageFilter += ",drawtext=text='$EscapedName':fontcolor=white:fontsize=$($Config.FontSize):box=1:boxcolor=black@0.5:x=10:y=10"
        }

        $FfmpegInputArgs += "-i", $File.Name
        $Filters += "[${i}:v]${ImageFilter}[v$i]"
        $Layouts += "${PosX}_${PosY}"
        
        $ColHeights[$TargetCol] += ($ScaledH + $Config.Gap)
        $ColFileCounts[$TargetCol]++
        [void]$ColFileLists[$TargetCol].Add($File.Name)
        $CurrentCol = ($TargetCol + 1) % $Config.ColumnCount
    }

    $Config | Add-Member -NotePropertyName 'FfmpegInputArgs' -NotePropertyValue $FfmpegInputArgs -Force
    $Config | Add-Member -NotePropertyName 'Filters' -NotePropertyValue $Filters -Force
    $Config | Add-Member -NotePropertyName 'Layouts' -NotePropertyValue $Layouts -Force
    $Config | Add-Member -NotePropertyName 'ColHeights' -NotePropertyValue $ColHeights -Force
    $Config | Add-Member -NotePropertyName 'ColFileCounts' -NotePropertyValue $ColFileCounts -Force
    $Config | Add-Member -NotePropertyName 'ColFileLists' -NotePropertyValue $ColFileLists -Force
}

# =======================================================
# 主流程区
# =======================================================

$InputFolder = (Get-Location).Path 
$IsDebug = $PSBoundParameters.ContainsKey('Debug') -and $PSBoundParameters['Debug']

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue) -or -not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    Write-Error "未找到 FFmpeg 或 FFprobe，请确保它们已添加至系统环境变量中。"
    return
}

$TargetFolders = @(Get-Item -LiteralPath $InputFolder)
if ($Depth -gt 0) {
    $TargetFolders += Get-ChildItem -LiteralPath $InputFolder -Directory -Recurse -Depth ($Depth - 1)
}

foreach ($TargetFolderItem in $TargetFolders) {
    $AbsoluteInputPath = $TargetFolderItem.FullName
    $ParentPath = Split-Path -Parent $AbsoluteInputPath
    if (-not $ParentPath) { $ParentPath = $AbsoluteInputPath }
    
    $FolderName = Split-Path -Leaf $AbsoluteInputPath
    if (-not $FolderName) { $FolderName = "Root" }
    
    # --- 动态构建文件名后缀 ---
    $Suffix = "masonry"
    if (-not [string]::IsNullOrWhiteSpace($CropSize)) {
        # 将 CropSize 转换为小写追加到文件名 (例如 auto, 4x3)
        $Suffix += "." + $CropSize.ToLower()
    }

    $AbsoluteOutputFile = [System.IO.Path]::GetFullPath((Join-Path $ParentPath "$FolderName.$Suffix.jpg"))
    $AbsoluteFilterPath = [System.IO.Path]::GetFullPath((Join-Path $ParentPath "$FolderName.$Suffix.filter.txt"))
    $AbsoluteCsvPath = [System.IO.Path]::GetFullPath((Join-Path $ParentPath "$FolderName.$Suffix.layout.csv"))
    # --------------------------

    Write-Host "`n=======================================================" -ForegroundColor Cyan
    Write-Host "开始处理目录: $AbsoluteInputPath" -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan

    Write-Host "--- 1. 路径配置确认 ---" -ForegroundColor Cyan
    Write-Host "执行目录 (素材): $AbsoluteInputPath"
    Write-Host "目标父目录: $ParentPath"
    Write-Host "输出文件: $AbsoluteOutputFile"
    Write-Host "滤镜脚本: $AbsoluteFilterPath"
    if ($IsDebug) { Write-Host "统计文件: $AbsoluteCsvPath" }

    # 1. 智能媒体探测
    Write-Host "`n--- 2. 正在扫描素材 ---" -ForegroundColor Cyan
    $ValidFiles = @()
    $AllFiles = Get-ChildItem -LiteralPath $AbsoluteInputPath -File

    if ($Sort -eq "Smart") {
        $AllFiles = $AllFiles | Sort-Object { [regex]::Replace($_.Name, '\d+', { $args[0].Value.PadLeft(20, '0') }) }
    }
    else {
        $AllFiles = $AllFiles | Sort-Object Name
    }

    foreach ($File in $AllFiles) {
        if ($File.FullName -in @($AbsoluteOutputFile, $AbsoluteFilterPath, $AbsoluteCsvPath)) { continue }

        $MediaInfo = Get-MediaInfo -FilePath $File.FullName
        if ($null -ne $MediaInfo) {
            $ValidFiles += [PSCustomObject]@{
                File   = $File
                Width  = $MediaInfo.Width
                Height = $MediaInfo.Height
            }
        }
    }

    if ($ValidFiles.Count -eq 0) { 
        Write-Warning "目录 [$AbsoluteInputPath] 中没有可处理的图片，跳过。"
        continue 
    }

    Write-Host "成功找到 $($ValidFiles.Count) 张图片。" -ForegroundColor Green

    # 1.5 计算裁剪尺寸信息
    $CropInfo = Get-CropInfo -ValidFiles $ValidFiles -CropSize $CropSize

    # 2. 准备上下文对象并计算布局
    Write-Host "`n--- 3. 正在计算瀑布流布局 ---" -ForegroundColor Cyan
    
    $LayoutContext = [PSCustomObject]@{
        CanvasWidth   = $CanvasWidth
        ColumnCount   = $ColumnCount
        Tolerance     = $Tolerance
        Gap           = $Gap
        ShowFileName  = $ShowFileName
        FontSize      = $FontSize
        IsUniformMode = $CropInfo.IsUniformMode
        TargetRatioW  = $CropInfo.TargetRatioW
        TargetRatioH  = $CropInfo.TargetRatioH
    }

    Get-MasonryLayout -ValidFiles $ValidFiles -Config $LayoutContext

    # 3. 写入 Filter Script
    Write-Host "`n--- 4. 写入滤镜脚本 ---" -ForegroundColor Cyan
    $VLabels = ""
    for ($k = 0; $k -lt $ValidFiles.Count; $k++) { $VLabels += "[v$k]" }
    
    $FinalFilter = ($LayoutContext.Filters -join ";`n") + ";`n" + $VLabels + "xstack=inputs=$($ValidFiles.Count):layout=$($LayoutContext.Layouts -join '|'):fill=$BackgroundColor"
    $FinalFilter | Out-File -LiteralPath $AbsoluteFilterPath -Encoding utf8 -Force

    # 4. 运行 FFmpeg
    Write-Host "`n--- 5. 启动渲染 ---" -ForegroundColor Yellow
    Push-Location -LiteralPath $AbsoluteInputPath

    $FfmpegCommandArgs = @("-hide_banner", "-loglevel", "warning")
    $FfmpegCommandArgs += $LayoutContext.FfmpegInputArgs
    $FfmpegCommandArgs += "-/filter_complex", $AbsoluteFilterPath, "-y", $AbsoluteOutputFile

    # [新增] 打印最终拼接好的完整 FFmpeg 执行命令，使用灰色输出以免太刺眼
    Write-Host "即将执行的完整命令:" -ForegroundColor Gray
    Write-Host "ffmpeg $($FfmpegCommandArgs -join ' ')" -ForegroundColor DarkGray
    

    try {
        & ffmpeg @FfmpegCommandArgs
    }
    catch {
        Write-Error "执行 FFmpeg 时发生严重异常: $_"
    }
    finally {
        Pop-Location
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n[成功] 文件已生成: $AbsoluteOutputFile" -ForegroundColor Green
        }
        else {
            Write-Host "`n[失败] FFmpeg 渲染出错 (ExitCode: $LASTEXITCODE)。" -ForegroundColor Red
        }

        # 5. Debug 统计文件与清理
        if ($IsDebug) {
            $CsvRows = @()
            $CsvRows += ($LayoutContext.ColFileCounts -join ",")
            $CsvRows += ($LayoutContext.ColHeights -join ",")
            
            $MaxRows = ($LayoutContext.ColFileCounts | Measure-Object -Maximum).Maximum
            for ($r = 0; $r -lt $MaxRows; $r++) {
                $RowNames = @()
                for ($c = 0; $c -lt $ColumnCount; $c++) {
                    if ($r -lt $LayoutContext.ColFileLists[$c].Count) {
                        $RowNames += "`"$($LayoutContext.ColFileLists[$c][$r])`""
                    }
                    else {
                        $RowNames += ""
                    }
                }
                $CsvRows += ($RowNames -join ",")
            }
            $CsvRows -join "`r`n" | Out-File -LiteralPath $AbsoluteCsvPath -Encoding utf8 -Force
            Write-Host "布局统计已保存至: $AbsoluteCsvPath" -ForegroundColor Gray
        }
        else {
            if (Test-Path -LiteralPath $AbsoluteFilterPath) { Remove-Item -LiteralPath $AbsoluteFilterPath -Force }
            if (Test-Path -LiteralPath $AbsoluteCsvPath) { Remove-Item -LiteralPath $AbsoluteCsvPath -Force }
            Write-Host "已清理临时滤镜文件。" -ForegroundColor Gray
        }
    }
}

Write-Host "`n全部处理完成！" -ForegroundColor Green
<#
.SYNOPSIS
    使用 FFmpeg 实现瀑布流图片拼接。
    将多张图片拼接成符合指定宽度和列数的瀑布流长图。

.DESCRIPTION
    该脚本扫描指定目录下的所有图片，根据图片原始比例计算缩放后的高度，
    并动态生成瀑布流布局。可以通过命令行参数自定义输出的列数、画布宽度、间隙大小、背景颜色等。
    它是从 scripts/ff_masonry.ps1 迁移而来的，并复用了项目中的模块。

.PARAMETER Sort
    文件名排序方式。'Smart'（数字顺序，默认）、'Name'（字母顺序）或 'VerticalRatio'（按缩放后的高度比例降序）。
    [高级玩法] 关于 -Sort VerticalRatio：
    选择按纵向比例 `VerticalRatio` 排序（通过高宽比算出最终实际占用高度并降序排列），将自动应用经典的贪心装箱堆叠算法（Bin Packing Heuristics - FFD / 最小加工时间 LPT）。
    让特别长的竖图优先寻找最短列占坑，用小又扁的横图留到最后去当“填缝剂”。配合设置一定的 Tolerance 容差，
    可以在不破坏局部横向阅读体验的情况下，极大地吸收生成图底部的“犬牙交错”高度差值。

.EXAMPLE
    pw2401 ff-masonry
    使用默认参数运行，将会把当前目录下的图片拼成列数为 5、宽度 3000、白色背景的瀑布流。

.EXAMPLE
    pw2401 ff-masonry -ColumnCount 3 -CanvasWidth 1920 -BackgroundColor "black" -Gap 10
    将图片拼成 3 列，总宽度 1920 像素，背景设为黑色，图片间距 10 像素。
#>

[CmdletBinding()]
param (
    [Parameter(HelpMessage = "画布的整体宽度（像素）。默认 3000")]
    [int]$CanvasWidth = 3000,

    [Parameter(HelpMessage = "瀑布流的列数。默认 5。")]
    [int]$ColumnCount = 5,

    [Parameter(HelpMessage = "是否在每列内上下倒序。搭配 -Sort VerticalRatio 时，能让本在底缝的小矮图跑到顶部先声夺人，巨幅长图镇场在底部。")]
    [switch]$ReverseColumn,

    [Parameter(HelpMessage = "排序容差系数。设置为极小值(如 0.5)可以兼顾排序和底部对齐，默认 0.5。")]
    [double]$Tolerance = 0.5,

    [Parameter(HelpMessage = "图片之间的间隙大小（像素）。默认 0。")]
    [int]$Gap = 0,

    [Parameter(HelpMessage = "画布的背景颜色（支持英文颜色词或十六进制如 0xFFFFFF）。默认 'white'。")]
    [string]$BackgroundColor = "white",

    [Parameter(HelpMessage = "是否在图片上方显示文件名。默认 `$false。")]
    [bool]$ShowFileName = $false,

    [Parameter(HelpMessage = "显示文件名时的字体大小。默认 20。")]
    [int]$FontSize = 20,

    [Parameter(HelpMessage = "文件名排序方式。'Smart'（数字顺序，默认）、'Name'（字母顺序）或 'VerticalRatio'（按最终占据高度的比例降序，让扁平的横图作为填缝剂填在最后）。")]
    [ValidateSet("Smart", "Name", "VerticalRatio")]
    [string]$Sort = "Smart",

    [Parameter(HelpMessage = "处理路径的深度。默认 0 即仅当前目录，1 表示包含所有一级子目录，以此类推。")]
    [int]$Depth = 0,

    [Parameter(HelpMessage = "统一裁剪尺寸格式 '宽x高' (如 '1920x1080')。设置为 'Auto' 时自动计算尺寸众数，不设置或为空则关闭统一裁剪（保留原始比例）。")]
    [string]$CropSize = "",

    [Parameter(HelpMessage = "输出的 JPEG 质量等级 (1-31)。数字越小质量越高、越清晰，同时也越大。默认 2 (高画质)。")]
    [int]$JpegQuality = 2
)

# =======================================================
# 辅助函数定义区 (Masonry 特有)
# =======================================================

# --- 1. 计算统一裁剪尺寸信息 ---
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
        Write-LogMessage "--- 分析图片尺寸众数 ---" -Level Info
        $SizeGroups = $ValidFiles | Group-Object -Property { "$($_.Width)x$($_.Height)" } | Sort-Object Count -Descending
        $ModeSize = $SizeGroups[0].Name
        Write-LogMessage "得出最常见尺寸 (众数): $ModeSize (占比 $($SizeGroups[0].Count) / $($ValidFiles.Count))" -Level Success
        
        $ModeParts = $ModeSize.Split('x')
        $Result.TargetRatioW = [int]$ModeParts[0]
        $Result.TargetRatioH = [int]$ModeParts[1]
    }
    elseif ($CropSize -match "^\d+x\d+$") {
        $ModeParts = $CropSize.Split('x')
        $Result.TargetRatioW = [int]$ModeParts[0]
        $Result.TargetRatioH = [int]$ModeParts[1]
        Write-LogMessage "指定强制裁剪比例尺寸: $($Result.TargetRatioW)x$($Result.TargetRatioH)" -Level Info
    }
    else {
        Write-LogMessage "CropSize 参数格式错误，应类似 '1920x1080' 或 'Auto'。功能已关闭，回退为原生比例瀑布流。" -Level Warning
        $Result.IsUniformMode = $false
    }

    return $Result
}

# --- 2. 计算瀑布流布局与滤镜参数 (基于上下文对象) ---
function Get-MasonryLayout {
    param (
        [Parameter(Mandatory = $true)][array]$ValidFiles,
        [Parameter(Mandatory = $true)][PSCustomObject]$Config
    )

    $ColWidth = [int]($Config.CanvasWidth / $Config.ColumnCount)
    $ColHeights = New-Object int[] $Config.ColumnCount
    $ColFileCounts = New-Object int[] $Config.ColumnCount
    
    # 追踪每列包含的图片，以便后续可能进行列内倒序排布
    $ColImages = New-Object System.Collections.ArrayList[] $Config.ColumnCount
    $ColFileLists = [System.Collections.ArrayList[]]::new($Config.ColumnCount)
    for ($j = 0; $j -lt $Config.ColumnCount; $j++) { 
        $ColFileLists[$j] = [System.Collections.ArrayList]::new() 
        $ColImages[$j] = [System.Collections.ArrayList]::new()
    }

    $FfmpegInputArgs = @()
    $Filters = @()
    $CurrentCol = 0

    for ($i = 0; $i -lt $ValidFiles.Count; $i++) {
        $FileObj = $ValidFiles[$i]
        $File = $FileObj.File
        $W = $FileObj.Width
        $H = $FileObj.Height

        if ($W -le 0 -or $H -le 0) { continue }

        if ($Config.IsUniformMode -and $Config.TargetRatioW -gt 0) {
            $ScaledH = [int]($ColWidth * $Config.TargetRatioH / $Config.TargetRatioW)
            $ImageFilter = "scale=${ColWidth}:${ScaledH}:force_original_aspect_ratio=increase:flags=lanczos,crop=${ColWidth}:${ScaledH}"
        }
        else {
            $ScaledH = [int]($ColWidth * $H / $W)
            $ImageFilter = "scale=${ColWidth}:-1:flags=lanczos"
        }

        $MinH = $ColHeights[0]; $ShortestIdx = 0
        for ($j = 1; $j -lt $Config.ColumnCount; $j++) {
            if ($ColHeights[$j] -lt $MinH) { $MinH = $ColHeights[$j]; $ShortestIdx = $j }
        }

        $TargetCol = if (($ColHeights[$CurrentCol] - $MinH) -gt ($ScaledH * $Config.Tolerance)) { $ShortestIdx } else { $CurrentCol }
        $PosX = $TargetCol * ($ColWidth + $Config.Gap)
        $OldH = $ColHeights[$TargetCol]
        $NewH = $OldH + $ScaledH + $Config.Gap

        Write-LogMessage "[Layout] [$i] $($File.Name) | Origin: ${W}x${H} | ScaledH: $ScaledH | Col: $TargetCol | MathOldH: $OldH | MathNewH: $NewH" -Level Info

        if ($Config.ShowFileName) {
            $EscapedName = $File.Name.Replace(":", "\\:").Replace("'", "").Replace("[", "\[").Replace("]", "\]")
            $ImageFilter += ",drawtext=text='$EscapedName':fontcolor=white:fontsize=$($Config.FontSize):box=1:boxcolor=black@0.5:x=10:y=10"
        }

        $FfmpegInputArgs += "-i", $File.FullName
        $Filters += "[${i}:v]${ImageFilter}[v$i]"
        
        # 存下分配信息，用来二次构建实际坐标
        [void]$ColImages[$TargetCol].Add([PSCustomObject]@{ Index = $i; ScaledH = $ScaledH; PosX = $PosX })
        
        $ColHeights[$TargetCol] = $NewH
        $ColFileCounts[$TargetCol]++
        [void]$ColFileLists[$TargetCol].Add($File.Name)
        $CurrentCol = ($TargetCol + 1) % $Config.ColumnCount
    }

    # --------- 二次生成真实 Y 坐标 (处理逆序需求) ---------
    $LayoutsArray = New-Object string[] $ValidFiles.Count
    for ($c = 0; $c -lt $Config.ColumnCount; $c++) {
        $ColList = $ColImages[$c]
        
        if ($Config.ReverseColumn) {
            $ColList.Reverse()
            # 同步翻转统计名单以匹配最终视觉
            $ColFileLists[$c].Reverse()
        }

        $CurrentY = 0
        foreach ($ImgData in $ColList) {
            $Idx = $ImgData.Index
            $LayoutsArray[$Idx] = "$($ImgData.PosX)_${CurrentY}"
            $CurrentY += $ImgData.ScaledH + $Config.Gap
        }
    }

    $Config | Add-Member -NotePropertyName 'FfmpegInputArgs' -NotePropertyValue $FfmpegInputArgs -Force
    $Config | Add-Member -NotePropertyName 'Filters' -NotePropertyValue $Filters -Force
    $Config | Add-Member -NotePropertyName 'Layouts' -NotePropertyValue $LayoutsArray -Force
    $Config | Add-Member -NotePropertyName 'ColHeights' -NotePropertyValue $ColHeights -Force
    $Config | Add-Member -NotePropertyName 'ColFileCounts' -NotePropertyValue $ColFileCounts -Force
    $Config | Add-Member -NotePropertyName 'ColFileLists' -NotePropertyValue $ColFileLists -Force
}

# =======================================================
# 主流程区
# =======================================================

$runtime = $global:GlobalConfig.runtime
Update-Target -suffix ".masonry"
$InputFolder = $runtime.WorkDir
$TargetFolder = $runtime.TargetDir
$IsDebug = $runtime.IsDebug

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue) -or -not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    Write-LogMessage "未找到 FFmpeg 或 FFprobe，请确保它们已添加至系统环境变量中。" -Level Error
    return
}

$TargetFolders = Get-DirectoryDepth -Path $InputFolder -Depth $Depth

foreach ($TargetFolderItem in $TargetFolders) {
    $AbsoluteInputPath = $TargetFolderItem.FullName
    $RelativePath = $AbsoluteInputPath.Substring($InputFolder.Length).TrimStart("\")
    
    if ([string]::IsNullOrEmpty($RelativePath)) {
        $OutputBaseDir = $TargetFolder
        $FolderName = Split-Path -Leaf $AbsoluteInputPath
        if (-not $FolderName) { $FolderName = "Root" }
    } else {
        $RelativeParent = Split-Path -Parent $RelativePath
        $OutputBaseDir = Join-Path -Path $TargetFolder -ChildPath $RelativeParent
        $FolderName = Split-Path -Leaf $RelativePath
    }

    if (-not (Test-Path -LiteralPath $OutputBaseDir)) {
        New-Item -Path $OutputBaseDir -ItemType Directory -Force | Out-Null
    }
    
    # --- 动态构建文件名后缀 ---
    $Suffix = "masonry"
    if (-not [string]::IsNullOrWhiteSpace($CropSize)) {
        $Suffix += "." + $CropSize.ToLower()
    }

    $AbsoluteOutputFile = [System.IO.Path]::GetFullPath((Join-Path $OutputBaseDir "$FolderName.$Suffix.jpg"))
    $AbsoluteFilterPath = [System.IO.Path]::GetFullPath((Join-Path $OutputBaseDir "$FolderName.$Suffix.filter.txt"))
    $AbsoluteCsvPath = [System.IO.Path]::GetFullPath((Join-Path $OutputBaseDir "$FolderName.$Suffix.layout.csv"))
    # --------------------------

    Write-LogMessage "`n=======================================================" -Level Info
    Write-LogMessage "开始处理目录: $AbsoluteInputPath" -Level Info
    Write-LogMessage "=======================================================" -Level Info

    Write-LogMessage "--- 1. 路径配置确认 ---" -Level Info
    Write-LogMessage "执行目录 (素材): $AbsoluteInputPath"
    Write-LogMessage "目标输出目录: $OutputBaseDir"
    Write-LogMessage "输出文件: $AbsoluteOutputFile"
    if ($IsDebug) { 
        Write-LogMessage "滤镜脚本: $AbsoluteFilterPath"
        Write-LogMessage "统计文件: $AbsoluteCsvPath" 
    }

    # 1. 智能媒体探测
    Write-LogMessage "`n--- 2. 扫描素材并计算瀑布流布局 ---" -Level Info
    $ValidFiles = @()
    $AllFiles = Get-ChildItem -LiteralPath $AbsoluteInputPath -File

    if ($Sort -eq "Smart") {
        $AllFiles = $AllFiles | Sort-Object { [regex]::Replace($_.Name, '\d+', { $args[0].Value.PadLeft(20, '0') }) }
    }
    elseif ($Sort -eq "Name") {
        $AllFiles = $AllFiles | Sort-Object Name
    }

    foreach ($File in $AllFiles) {
        if ($File.FullName -in @($AbsoluteOutputFile, $AbsoluteFilterPath, $AbsoluteCsvPath)) { continue }

        # 使用模块中的 Get-MediaInfo
        $MediaInfo = Get-MediaInfo -Path $File.FullName
        if ($MediaInfo.Type -eq "image" -or ($MediaInfo.Type -eq "video" -and $MediaInfo.Width -gt 0)) {
            
            # 使用 File.psm1 模块封装的函数获取真实的 EXIF 宽和高
            $TrueInfo = Get-ImageTrueDimensions -FilePath $File.FullName -RawWidth $MediaInfo.Width -RawHeight $MediaInfo.Height

            if ($IsDebug) {
                Write-LogMessage "[EXIF Check] $($File.Name) | Raw: $($MediaInfo.Width)x$($MediaInfo.Height) | EXIF: $($TrueInfo.Exif) | Final: $($TrueInfo.Width)x$($TrueInfo.Height)" -Level Info
            }

            $ValidFiles += [PSCustomObject]@{
                File   = $File
                Width  = $TrueInfo.Width
                Height = $TrueInfo.Height
            }
        }
    }

    if ($ValidFiles.Count -eq 0) { 
        Write-LogMessage "目录 [$AbsoluteInputPath] 中没有可处理的图片，跳过。" -Level Warning
        continue 
    }

    # 按相对高度比例排序（等宽缩放后的实际高度降序）
    if ($Sort -eq "VerticalRatio") {
        $ValidFiles = @($ValidFiles | Sort-Object -Property @{ Expression = { $_.Height / $_.Width }; Descending = $true })
        Write-LogMessage "已按照图片目标缩放纵向比例 (VerticalRatio) 降序重排。" -Level Info
    }

    Write-LogMessage "成功找到 $($ValidFiles.Count) 张图片。" -Level Success

    # 1.5 计算裁剪尺寸信息
    $CropInfo = Get-CropInfo -ValidFiles $ValidFiles -CropSize $CropSize

    # 2. 准备上下文对象并计算布局
    $LayoutContext = [PSCustomObject]@{
        CanvasWidth   = $CanvasWidth
        ColumnCount   = $ColumnCount
        ReverseColumn = $ReverseColumn
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
    Write-LogMessage "`n--- 3. 生成滤镜脚本 ---" -Level Info
    $VLabels = ""
    for ($k = 0; $k -lt $ValidFiles.Count; $k++) { $VLabels += "[v$k]" }
    
    $FinalFilter = ($LayoutContext.Filters -join ";`n") + ";`n" + $VLabels + "xstack=inputs=$($ValidFiles.Count):layout=$($LayoutContext.Layouts -join '|'):fill=$BackgroundColor"
    $FinalFilter | Out-File -LiteralPath $AbsoluteFilterPath -Encoding utf8 -Force

    # 4. 运行 FFmpeg
    Write-LogMessage "`n--- 4. 启动渲染 ---" -Level Info
    Push-Location -LiteralPath $AbsoluteInputPath

    $FfmpegCommandArgs = @("-hide_banner", "-loglevel", "warning")
    $FfmpegCommandArgs += $LayoutContext.FfmpegInputArgs
    $FfmpegCommandArgs += "-/filter_complex", $AbsoluteFilterPath, "-q:v", "$JpegQuality", "-y", $AbsoluteOutputFile

    Write-LogMessage "即将执行的完整命令: ffmpeg $($FfmpegCommandArgs -join ' ')" -Level Info
    
    try {
        & ffmpeg @FfmpegCommandArgs
    }
    catch {
        Write-LogMessage "执行 FFmpeg 时发生严重异常: $_" -Level Error
    }
    finally {
        Pop-Location
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "`n[成功] 文件已生成: $AbsoluteOutputFile" -Level Success
        }
        else {
            Write-LogMessage "`n[失败] FFmpeg 渲染出错 (ExitCode: $LASTEXITCODE)。" -Level Error
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
            Write-LogMessage "布局统计已保存至: $AbsoluteCsvPath" -Level Info
        }
        else {
            if (Test-Path -LiteralPath $AbsoluteFilterPath) { Remove-Item -LiteralPath $AbsoluteFilterPath -Force }
            if (Test-Path -LiteralPath $AbsoluteCsvPath) { Remove-Item -LiteralPath $AbsoluteCsvPath -Force }
            Write-LogMessage "已清理临时滤镜文件。" -Level Info
        }
    }
}

Write-LogMessage "`n正在清理目标目录中的空文件夹..." -Level Info
if (Test-Path -LiteralPath $TargetFolder) {
    Remove-EmptyDirectories -Path $TargetFolder
}

Write-LogMessage "全部处理完成！" -Level Success

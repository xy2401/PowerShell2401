[CmdletBinding(PositionalBinding = $false)]
param(
   
    [Parameter(HelpMessage = "处理路径的深度。默认 0 即处理当前目录下的文件，1 表示处理一级子文件夹内的文件。")]
    [int]$Depth = 1,

    [Parameter(HelpMessage = "允许分组的类型数组。'P'代表图片分类，'V'代表视频分类，'D'代表按视频时长分类，'S'代表按文件大小分类")]
    [string[]]$Groups = @("P", "V"),

    [Parameter(HelpMessage = "视频时长分组边界 (秒数组)")]
    [int[]]$DurationBins = @(60, 600, 3600),

    [Parameter(HelpMessage = "文件大小分组边界 (字节数组)")]
    [long[]]$SizeBins = @(1MB, 10MB, 100MB, 1GB)
)

# 辅助函数：将秒数转换为友好格式 (如 1m, 1h)
function Format-DurationText {
    param([double]$seconds)
    if ($seconds -lt 60) { return "$($seconds)s" }
    if ($seconds -lt 3600) { return "$([Math]::Round($seconds/60))m" }
    return "$([Math]::Round($seconds/3600))h"
}

# 辅助函数：根据边界获取文件夹名称
function Get-BinFolderName {
    param(
        [double]$Value,
        [Array]$Bins,
        [string]$Prefix,
        [scriptblock]$Formatter
    )

    # 排序确保 Bins 是递增的
    $sortedBins = $Bins | Sort-Object

    for ($i = 0; $i -lt $sortedBins.Count; $i++) {
        if ($Value -lt $sortedBins[$i]) {
            if ($i -eq 0) {
                $label = "0-$(& $Formatter $sortedBins[$i])"
            }
            else {
                $label = "$(& $Formatter $sortedBins[$i-1])-$(& $Formatter $sortedBins[$i])"
            }
            return "$($Prefix)_$label"
        }
    }

    # 超过最大边界
    return "$($Prefix)_$(& $Formatter $sortedBins[-1])+"
}

$runtime = $global:GlobalConfig.runtime
$Path = $runtime.WorkDir
 
# 动态确定一个日志文件名字
$logFileName = "dir-group_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Initialize-Log $logFileName

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-LogMessage -message "[Error] 找不到目标目录: $Path"
    return
}

# 严格锁定处理只在指定的精确深度级产生 (使用通用深度寻层逻辑)
$targetDirs = Get-DirectoryDepth -Path $Path -Depth $Depth

Write-LogMessage -message "=> [Dir-Group] 开始处理物理目录排版分组，共选中 $($targetDirs.Count) 个目录"

foreach ($dir in $targetDirs) {
    $dirFullName = $dir.FullName
    Write-LogMessage -message "-----------------------------------------------"
    Write-LogMessage -message "正在处理: $dirFullName"

    # 只获取该目录极其第一层的直属文件 (不包含递归里的孙子辈文件)
    $files = Get-ChildItem -LiteralPath $dirFullName -File
    $movedP = 0
    $movedV = 0
    $movedD = 0
    $movedS = 0

    foreach ($file in $files) {
        $type = Get-FileType -FileName $file.Name
        $targetFolderName = $null

        # 检查是否属于需要收容到专属维度的媒体类型
        if ($type -eq "image" -and $Groups -contains "P") {
            $targetFolderName = "P"
            $movedP++
        }
        elseif ($type -eq "video" -and $Groups -contains "D") {
            # 按视频时长分类
            $info = Get-MediaInfo -Path $file.FullName
            $duration = $info.Duration
            if ($duration -gt 0) {
                $targetFolderName = Get-BinFolderName -Value $duration -Bins $DurationBins -Prefix "V" -Formatter ${function:Format-DurationText}
                $movedD++
            }
            elseif ($Groups -contains "V") {
                # 如果时长获取失败但要求 V 分类，退回到 V
                $targetFolderName = "V"
                $movedV++
            }
        }
        elseif ($type -eq "video" -and $Groups -contains "V") {
            $targetFolderName = "V"
            $movedV++
        }
        
        # 如果以上都没中，且要求按大小分类
        if (-not $targetFolderName -and $Groups -contains "S") {
            $targetFolderName = Get-BinFolderName -Value $file.Length -Bins $SizeBins -Prefix "S" -Formatter ${function:Format-SizeText}
            $movedS++
        }

        if ($targetFolderName) {
            $destPath = Join-Path $dirFullName $targetFolderName
            # 懒惰建立对应的归置夹（即只要发生了命中的相关文件，才去建对应的空壳）
            if (-not (Test-Path -LiteralPath $destPath -PathType Container)) {
                New-Item -Path $destPath -ItemType Directory -Force | Out-Null
                Write-LogMessage -message " [+] 按需成功建立分组隔离目录: $targetFolderName"
            }
            
            try {
                Move-Item -LiteralPath $file.FullName -Destination $destPath -Force -ErrorAction Stop
            }
            catch {
                Write-LogMessage -message " [Error] 无法将文件移入对应分组区 $($file.Name): $_"
            }
        }
    }

    if ($movedP -eq 0 -and $movedV -eq 0 -and $movedD -eq 0 -and $movedS -eq 0) {
        Write-LogMessage -message " 状态: 该层级没有匹配到游离在外部的所需文件，未发生物理位移"
    }
    else {
        $msg = " 状态: 本层归档打包完毕 (整理收纳了: "
        if ($movedP -gt 0) { $msg += "$movedP 张图集 " }
        if ($movedV -gt 0) { $msg += "$movedV 部影片 " }
        if ($movedD -gt 0) { $msg += "$movedD 部影片(时长分组) " }
        if ($movedS -gt 0) { $msg += "$movedS 个文件(大小分组) " }
        $msg += ")"
        Write-LogMessage -message $msg
    }
}

Write-LogMessage -message "=> [Dir-Group] 处理完成！"

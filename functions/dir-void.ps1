<#
.SYNOPSIS
    发现并清理空文件夹或仅含单个子目录的冗余文件夹。

.DESCRIPTION
    1. 发现空文件夹（无文件，无子目录）。
    2. 发现冗余文件夹（无文件，仅有一个子文件夹）。
    3. 使用 -Y 参数执行清理：
       - 删除空文件夹。
       - 将冗余文件夹内的唯一子文件夹上移一层。如果目标位置已存在同名目录，则在新名字后追加 .move。

.PARAMETER Depth
    处理深度。默认 0 即仅当前目录，1 表示包含所有一级子目录，以此类推。

.PARAMETER Y
    确认执行开关。如果不加此参数，仅进行扫描和预览。
#>

param(
    [int]$Depth = 0,
    [switch]$Y
)

$runtime = $global:GlobalConfig.runtime
$workDir = $runtime.WorkDir

# 动态确定一个日志文件名字
$logFileName = "dir-void_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Init-Log $logFileName

Log-Message "Scanning for 'void' directories (Depth: $Depth)..." -Level Info
if ($Y) { Log-Message "[Mode] Cleanup enabled (-Y detected)" -Level Warning }

# 使用通用深度寻层逻辑获取目标目录
$targetDirs = Get-Directory-Depth -Path $workDir -Depth $Depth

$emptyCount = 0
$redundantCount = 0

foreach ($dir in $targetDirs) {
    $dirPath = $dir.FullName
    if (-not (Test-Path -LiteralPath $dirPath)) { continue }

    # 获取直属内容（包含隐藏文件/文件夹以便准确判断是否为空）
    $items = Get-ChildItem -LiteralPath $dirPath -Force
    $files = $items | Where-Object { -not $_.PSIsContainer }
    $subDirs = $items | Where-Object { $_.PSIsContainer }

    $fileCount = if ($null -eq $files) { 0 } else { $files.Count }
    $dirCount = if ($null -eq $subDirs) { 0 } else { $subDirs.Count }

    # 逻辑 A: 绝对空目录
    if ($fileCount -eq 0 -and $dirCount -eq 0) {
        $emptyCount++
        Log-Message "[Empty] $dirPath" -Level Warning
        if ($Y) {
            try {
                Remove-Item -LiteralPath $dirPath -Force -ErrorAction Stop
                Log-Message "  -> Deleted." -Level Success
            }
            catch {
                Log-Message "  -> [Error] Failed to delete: $_" -Level Error
            }
        }
    }
    # 逻辑 B: 冗余目录 (仅含一个子目录)
    elseif ($fileCount -eq 0 -and $dirCount -eq 1) {
        $redundantCount++
        $targetSubDir = $subDirs[0]
        Log-Message "[Redundant] $dirPath (Contains: $($targetSubDir.Name))" -Level Warning
        
        if ($Y) {
            $parentDir = $dir.Parent.FullName
            if (-not $parentDir) { 
                Log-Message "  -> [Skip] Cannot move subfolder of root directory." -Level Warning
                continue 
            }

            $destPath = Join-Path -Path $parentDir -ChildPath $targetSubDir.Name
            
            # 处理命名冲突
            if (Test-Path -LiteralPath $destPath) {
                $destPath += ".move"
                Log-Message "  -> Conflict detected, renaming to: $($targetSubDir.Name).move" -Level Info
            }

            try {
                # 移动子文件夹
                Move-Item -LiteralPath $targetSubDir.FullName -Destination $destPath -ErrorAction Stop
                # 删除现在的空父目录
                Remove-Item -LiteralPath $dirPath -Force -ErrorAction Stop
                Log-Message "  -> Subfolder moved and redundant parent removed." -Level Success
            }
            catch {
                Log-Message "  -> [Error] Failed to move/cleanup: $_" -Level Error
            }
        }
    }
}

Log-Message "`nScan Complete." -Level Info
Log-Message "Found $emptyCount empty folders and $redundantCount redundant folders." -Level Info
if (-not $Y -and ($emptyCount + $redundantCount -gt 0)) {
    Log-Message "Hint: Run with '-Y' to perform cleanup." -Level Info
}

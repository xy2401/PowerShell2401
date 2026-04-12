<#
.SYNOPSIS
    发现并清理空文件夹或仅含单个子目录的冗余文件夹。

.DESCRIPTION
    1. 发现空文件夹（无文件，无子目录）。
    2. 发现冗余文件夹（无文件，仅有一个子文件夹）。
    3. 使用 -Y 参数执行清理：
       - 删除空文件夹。
       - 将冗余文件夹内的唯一子文件夹上移一层。如果目标位置已存在同名目录，则在新名字后追加 .move。

.PARAMETER Delete
    删除检查到的绝对空文件夹。

.PARAMETER MoveUp
    将冗余文件夹（仅包含单个子文件夹、无文件）内的子文件夹上移一层，并清理外层空壳。如果目标位置冲突，会加 .move 后缀。
#>

param(
    [int]$Depth = 0,
    [switch]$Delete,
    [switch]$MoveUp
)

# 判断是否为纯预览模式（没有提供任何清理动作）
$isPreview = (-not $Delete -and -not $MoveUp)

$runtime = $global:GlobalConfig.runtime
$workDir = $runtime.WorkDir

# 动态确定一个日志文件名字
$logFileName = "dir-void_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Initialize-Log $logFileName

Write-LogMessage "Scanning for 'void' directories (Depth: $Depth)..." -Level Info
if ($isPreview) { Write-LogMessage "[Mode] Preview (Check only)" -Level Info }
if ($Delete) { Write-LogMessage "[Mode] Delete empty directories enabled" -Level Warning }
if ($MoveUp) { Write-LogMessage "[Mode] Move-Up redundant directories enabled" -Level Warning }

# 使用通用深度寻层逻辑获取目标目录
$targetDirs = Get-DirectoryDepth -Path $workDir -Depth $Depth

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
        Write-LogMessage "[Empty] $dirPath" -Level Warning
        if ($Delete) {
            try {
                Remove-Item -LiteralPath $dirPath -Force -ErrorAction Stop
                Write-LogMessage "  -> Deleted." -Level Success
            }
            catch {
                Write-LogMessage "  -> [Error] Failed to delete: $_" -Level Error
            }
        }
    }
    # 逻辑 B: 冗余目录 (仅含一个子目录)
    elseif ($fileCount -eq 0 -and $dirCount -eq 1) {
        $redundantCount++
        $targetSubDir = $subDirs[0]
        Write-LogMessage "[Redundant] $dirPath (Contains: $($targetSubDir.Name))" -Level Warning
        
        if ($MoveUp) {
            $parentDir = $dir.Parent.FullName
            if (-not $parentDir) { 
                Write-LogMessage "  -> [Skip] Cannot move subfolder of root directory." -Level Warning
                continue 
            }

            $destPath = Join-Path -Path $parentDir -ChildPath $targetSubDir.Name
            
            $addedMoveSuffix = $false
            # 处理命名冲突
            if (Test-Path -LiteralPath $destPath) {
                $destPath += ".move"
                $addedMoveSuffix = $true
                Write-LogMessage "  -> Conflict detected, renaming to: $($targetSubDir.Name).move" -Level Info
            }

            try {
                # 移动子文件夹
                Move-Item -LiteralPath $targetSubDir.FullName -Destination $destPath -ErrorAction Stop
                # 删除现在的空父目录
                Remove-Item -LiteralPath $dirPath -Force -ErrorAction Stop
                Write-LogMessage "  -> Subfolder moved and redundant parent removed." -Level Success

                # 检查是否可以去掉 .move 后缀
                if ($addedMoveSuffix) {
                    $originalDestPath = $destPath.Substring(0, $destPath.Length - 5)
                    if (-not (Test-Path -LiteralPath $originalDestPath)) {
                        Rename-Item -LiteralPath $destPath -NewName (Split-Path $originalDestPath -Leaf) -ErrorAction Stop
                        Write-LogMessage "  -> Removed .move suffix as target name became available." -Level Success
                    }
                }
            }
            catch {
                Write-LogMessage "  -> [Error] Failed to move/cleanup: $_" -Level Error
            }
        }
    }
}

Write-LogMessage "`nScan Complete." -Level Info
Write-LogMessage "Found $emptyCount empty folders and $redundantCount redundant folders." -Level Info
if ($isPreview) {
    Write-LogMessage "Hint: Run with '-Delete' or '-MoveUp' to perform cleanup actions." -Level Info
}

<#
.SYNOPSIS
    遍历源目录中的所有子目录，并在目标目录中创建对应的子目录。

.DESCRIPTION
    该函数递归遍历源目录中的所有子目录，并在目标目录中创建对应的子目录。
    如果目标目录不存在，将自动创建目标目录。
    使用 -LiteralPath 参数以防止通配符解释。

.PARAMETER sourceDir
    源目录的路径，包含要复制的子目录。

.PARAMETER targetDir
    目标目录的路径，在此目录中创建对应的子目录。

.EXAMPLE
    Create-Directories -sourceDir "C:\Path\To\Source" -targetDir "C:\Path\To\Target"
    在目标目录 C:\Path\To\Target 中创建源目录 C:\Path\To\Source 中所有子目录的副本。

.NOTES
    该函数依赖于 PowerShell 的 Get-ChildItem 和 New-Item cmdlet 来遍历目录和创建子目录。
#>
function Create-Directories {
    param (
        [string]$sourceDir,
        [string]$targetDir
    )

    # 创建目标目录，如果不存在
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -Path $targetDir -ItemType Directory | Out-Null
    }
    # 使用 -LiteralPath 参数以防止通配符解释，遍历所有子目录并创建对应的目标目录
    Get-ChildItem -LiteralPath $sourceDir -Directory -Recurse | ForEach-Object {
        $subDir = $_.FullName
        $relativePath = $subDir.Substring($sourceDir.Length).TrimStart("\")
        $newTargetDir = Join-Path -Path $targetDir -ChildPath $relativePath

        if (-not (Test-Path -LiteralPath $newTargetDir)) {
            New-Item -Path $newTargetDir -ItemType Directory | Out-Null
        }
    }
}

<#
.SYNOPSIS
    获取指定深度的目录列表。
    
.DESCRIPTION
    Depth 为 0 时返回当前目录本身。
    Depth 为 1 时返回当前目录下的直接子目录。
    Depth 为 n 时递归到第 n 层。
    Depth >= 999 时，返回当前目录及其所有深度的子目录。
#>
function Get-Directory-Depth {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [int]$Depth = 0
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return @()
    }

    # 特殊逻辑：当深度 >= 999 时，递归返回所有目录（包括根目录）
    if ($Depth -ge 999) {
        return @(Get-Item -LiteralPath $Path) + @(Get-ChildItem -LiteralPath $Path -Directory -Recurse)
    }

    $targetDirs = @(Get-Item -LiteralPath $Path)
    for ($i = 0; $i -lt $Depth; $i++) {
        $nextLevel = @()
        foreach ($dir in $targetDirs) {
            $nextLevel += Get-ChildItem -LiteralPath $dir.FullName -Directory
        }
        $targetDirs = $nextLevel
    }

    return $targetDirs
}

<#
.SYNOPSIS
    递归删除指定目录下的所有空目录。

.DESCRIPTION
    该函数递归扫描指定目录，自底向上删除其中不包含任何文件或子目录的空文件夹。
    它对于清理由于提前预建目录结构而产生的冗余空文件夹非常有用。

.PARAMETER Path
    要处理的目标根目录的路径。不会删除根目录本身。
#>
function Remove-EmptyDirectories {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    # 获取所有子目录，然后按照路径长度倒序排序（自底向上）
    $directories = Get-ChildItem -LiteralPath $Path -Directory -Recurse |
        Sort-Object -Property @{Expression={$_.FullName.Length}; Descending=$true}

    foreach ($dir in $directories) {
        # 强制获取目录下的所有子项（包含隐藏文件等）
        $items = Get-ChildItem -LiteralPath $dir.FullName -Force
        if ($null -eq $items -or $items.Count -eq 0) {
            try {
                Remove-Item -LiteralPath $dir.FullName -Force -Recurse:$false
            } catch {
                Write-Warning "无法删除空目录: $($dir.FullName), 错误: $($_.Exception.Message)"
            }
        }
    }
}

Export-ModuleMember -Function Create-Directories, Get-Directory-Depth, Remove-EmptyDirectories

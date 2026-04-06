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
    if (-not (Test-Path -Path $targetDir)) {
        New-Item -Path $targetDir -ItemType Directory | Out-Null
    }
    # 使用 -LiteralPath 参数以防止通配符解释，遍历所有子目录并创建对应的目标目录
    Get-ChildItem -LiteralPath $sourceDir -Directory -Recurse | ForEach-Object {
        $subDir = $_.FullName
        $relativePath = $subDir.Substring($sourceDir.Length).TrimStart("\")
        $newTargetDir = Join-Path -Path $targetDir -ChildPath $relativePath

        if (-not (Test-Path -Path $newTargetDir)) {
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

Export-ModuleMember -Function Create-Directories, Get-Directory-Depth

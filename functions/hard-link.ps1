<#
.SYNOPSIS
    在同级目录下创建一个包含所有文件硬链接的镜像目录。

.DESCRIPTION
    该脚本会获取当前目录信息，并创建一个以 '.hardlink' 为后缀的目标目录。
    它会保持原有的目录层级结构，并将所有文件通过 PowerShell 原生的 HardLink 方式镜像到目标位置。
#>
param()

# 1. 更新 target (后缀为 .hardlink)
$suffix = ".hardlink"
Update-Target -suffix $suffix
$runtime = $global:GlobalConfig.runtime

Log-Message "开始创建硬链接镜像目录..." -Level Info
Log-Message "源目录: $($runtime.WorkDir)" -Level Info
Log-Message "目标目录: $($runtime.TargetDir)" -Level Info

# 2. 调用 lib/Directory.psm1 中的函数创建目录层级
Create-Directories -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir

# 3. 遍历文件并创建硬链接
$sourceDir = $runtime.WorkDir
$targetDir = $runtime.TargetDir

Get-ChildItem -LiteralPath $sourceDir -File -Recurse | ForEach-Object {
    $sourceFile = $_.FullName
    # 计算相对路径
    $relativePath = $sourceFile.Substring($sourceDir.Length).TrimStart("\")
    $targetFile = Join-Path -Path $targetDir -ChildPath $relativePath

    # 如果目标文件已存在，先删除
    if (Test-Path -LiteralPath $targetFile) {
        Remove-Item -LiteralPath $targetFile -Force
    }

    try {
        # 使用 PowerShell 原生硬链接命令
        New-Item -ItemType HardLink -Path $targetFile -Target $sourceFile | Out-Null
    }
    catch {
        Log-Message "创建硬链接失败: $relativePath" -Level Error
    }
}

Log-Message "硬链接目录创建完成！" -Level Success

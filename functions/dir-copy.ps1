<#
.SYNOPSIS
    在同级目录下创建一个纯拷贝的镜像目录，支持多种条件过滤。

.DESCRIPTION
    该脚本会获取当前目录信息，并创建一个以 '.copy' 为后缀的目标目录。
    支持按特定的文件后缀、文本内容、内容正则表达式或文件名正则表达式来筛选需要复制的文件。
    同时提供了一个拷贝后删除原文件的选项（相当于移动文件）。

.PARAMETER Extension
    指定要复制的文件名后缀数组（例如: html, css, .txt）。默认不区分大小写，且带不带前导点都可以。若未指定或为空，则复制所有后缀类型。

.PARAMETER DeleteOriginal
    一个开关参数。如果开启，复制成功后会将原始文件删除（类似于移动效果）。

.PARAMETER ContainsText
    指定要包含的纯文本内容。只有文件内容中包含了该字符串，文件才会被拷贝。适用于过滤包含特定代码或日志的文件。

.PARAMETER ContentRegex
    指定要匹配的正则表达式内容。只有文件内容匹配到了该正则表达式，文件才会被拷贝。

.PARAMETER NameRegex
    指定要匹配的文件名正则表达式。只有文件名（或其部分）匹配该正则表达式，文件才会被拷贝。
#>
param(
    [string[]]$Extension,
    [switch]$DeleteOriginal,
    [string]$ContainsText,
    [string]$ContentRegex,
    [string]$NameRegex
)

# 1. 更新 target (后缀为 .copy)
$suffix = ".copy"
Update-Target -suffix $suffix
$runtime = $global:GlobalConfig.runtime

Log-Message "开始拷贝文件..." -Level Info
Log-Message "源目录: $($runtime.WorkDir)" -Level Info
Log-Message "目标目录: $($runtime.TargetDir)" -Level Info

# 处理后缀名参数，统一处理前导 "."
$extList = @()
if ($Extension) {
    # 将后缀名统一为带点的方式
    $extList = $Extension | ForEach-Object {
        if ($_ -match '^\.') { $_ } else { ".$_" }
    }
}

# 2. 调用 lib/Directory.psm1 中的函数创建目录层级
Create-Directories -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir

# 3. 遍历文件并复制
$sourceDir = $runtime.WorkDir
$targetDir = $runtime.TargetDir
$copiedCount = 0

Get-ChildItem -LiteralPath $sourceDir -File -Recurse | ForEach-Object {
    $sourceFile = $_
    $sourcePath = $_.FullName
    $relativePath = $sourcePath.Substring($sourceDir.Length).TrimStart("\")
    $targetFile = Join-Path -Path $targetDir -ChildPath $relativePath

    # -- 过滤条件判断开始 --

    # 1. 过滤后缀名
    if ($extList.Count -gt 0) {
        if ($sourceFile.Extension -notin $extList) {
            return # 类似于 continue，跳过当前文件
        }
    }

    # 2. 过滤正则表达式文件名匹配
    if ([string]::IsNullOrWhiteSpace($NameRegex) -eq $false) {
        if ($sourceFile.Name -notmatch $NameRegex) {
            return
        }
    }

    # 3. 过滤文本内容 (纯文本匹配)
    if ([string]::IsNullOrWhiteSpace($ContainsText) -eq $false) {
        try {
            $match = Select-String -LiteralPath $sourcePath -SimpleMatch -Pattern $ContainsText -Quiet -ErrorAction Stop
            if (-not $match) {
                return
            }
        } catch {
            return # 当作不匹配处理
        }
    }

    # 4. 过滤正则表达式内容匹配
    if ([string]::IsNullOrWhiteSpace($ContentRegex) -eq $false) {
        try {
            $regexMatch = Select-String -LiteralPath $sourcePath -Pattern $ContentRegex -Quiet -ErrorAction Stop
            if (-not $regexMatch) {
                return
            }
        } catch {
            return
        }
    }

    # -- 过滤条件判断结束 --

    # 执行拷贝操作
    try {
        # 如果目标文件已存在，先删除
        if (Test-Path -LiteralPath $targetFile) {
            Remove-Item -LiteralPath $targetFile -Force
        }

        # 拷贝文件
        Copy-Item -LiteralPath $sourcePath -Destination $targetFile -Force
        $copiedCount++

        # 如果开启了删除选项，则删除原文件
        if ($DeleteOriginal) {
            Remove-Item -LiteralPath $sourcePath -Force
        }
    }
    catch {
        $errMsg = $_.Exception.Message
        Log-Message "拷贝文件失败: $relativePath - $errMsg" -Level Error
    }
}

Log-Message "拷贝目录操作完成！共拷贝 $copiedCount 个文件。" -Level Success
if ($DeleteOriginal) {
    Log-Message "已开启删除原始文件选项，符合条件的原始文件已被清理。" -Level Info
}

# 4. 清理目标目录中的空文件夹
Log-Message "正在清理目标目录中的空文件夹..." -Level Info
Remove-EmptyDirectories -Path $runtime.TargetDir
Log-Message "空文件夹清理完成！" -Level Success

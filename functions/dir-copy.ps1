<#
.SYNOPSIS
    在同级目录下创建一个纯拷贝的镜像目录，支持多种条件过滤。

.DESCRIPTION
    该脚本会获取当前目录信息，并创建一个以 '.copy' 为后缀的目标目录。
    支持按特定的文件后缀、文本内容、内容正则表达式或文件名正则表达式来筛选需要复制的文件。
    先复制到目标目录的临时文件，校验大小并完成替换后才允许删除原文件。
    复制或替换失败时保留源文件和已有目标文件，并以失败状态结束。

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

.EXAMPLE
    # ExampleId: extension-filter
    pw2401 dir-copy -Extension txt

    将当前目录中的文本文件复制到同级的 .copy 目录，并保持原目录结构。

.NOTES
    Requires: PowerShell
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

Write-LogMessage "开始拷贝文件..." -Level Info
Write-LogMessage "源目录: $($runtime.WorkDir)" -Level Info
Write-LogMessage "目标目录: $($runtime.TargetDir)" -Level Info

# 处理后缀名参数，统一处理前导 "."
$extList = @()
if ($Extension) {
    # 将后缀名统一为带点的方式
    $extList = $Extension | ForEach-Object {
        if ($_ -match '^\.') { $_ } else { ".$_" }
    }
}

# 3. 遍历文件并复制
$sourceDir = $runtime.WorkDir
$targetDir = $runtime.TargetDir
$copiedCount = 0
$failedCount = 0

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
    $temporaryPath = $null
    try {
        $targetParent = Split-Path -Path $targetFile -Parent
        [void][IO.Directory]::CreateDirectory($targetParent)
        $temporaryPath = Join-Path $targetParent ('.pw2401-' + [guid]::NewGuid().ToString('N') + '.tmp')
        Copy-Item -LiteralPath $sourcePath -Destination $temporaryPath -ErrorAction Stop
        if ((Get-Item -LiteralPath $temporaryPath -ErrorAction Stop).Length -ne $sourceFile.Length) {
            throw "复制后大小不一致: $relativePath"
        }
        Complete-FileReplacement -TemporaryPath $temporaryPath -Destination $targetFile
        $copiedCount++

        # 如果开启了删除选项，则删除原文件
        if ($DeleteOriginal) {
            Remove-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
        }
    }
    catch {
        $failedCount++
        $errMsg = $_.Exception.Message
        Write-LogMessage "拷贝文件失败: $relativePath - $errMsg" -Level Error
    }
    finally {
        if ($temporaryPath -and [IO.File]::Exists($temporaryPath)) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($failedCount -gt 0) {
    throw "拷贝操作有 $failedCount 个文件失败；已完成 $copiedCount 个文件的复制。"
}
Write-LogMessage "拷贝目录操作完成！共拷贝 $copiedCount 个文件。" -Level Success
if ($DeleteOriginal) {
    Write-LogMessage "已开启删除原始文件选项，符合条件的原始文件已被清理。" -Level Info
}

# 只为匹配文件创建目录，无需预扫描或清理整棵目标目录树。

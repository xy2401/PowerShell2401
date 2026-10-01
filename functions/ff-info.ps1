<#
.SYNOPSIS
    为目录中的媒体文件导出 ffprobe JSON 信息。

.DESCRIPTION
    递归扫描当前目录，将图片和视频的流及容器信息写入同级 .info 目录；其他文件使用硬链接保留目录镜像。

.PARAMETER RemainingArguments
    保留的附加参数，目前不参与处理。

.EXAMPLE
    # ExampleId: inspect-media
    pw2401 ff-info

    导出当前目录所有媒体文件的信息。

.NOTES
    Requires: ffmpeg, ffprobe
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    # 预留参数扩展
    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArguments
)

function Start-InfoTask {
    $suffix = ".info" 
    Update-Target -suffix $suffix
    $runtime = $global:GlobalConfig.runtime
    Initialize-Log  ( $runtime.TargetDirName + ".log"  )
    
    # 先创建所有目录
    New-Directories -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir
    $startTime = Get-Date
    Process-InfoDirectory -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir
    Write-LogMessage -message "Info extraction cost $(((Get-Date) - $startTime).TotalSeconds) Seconds"
}

function Process-InfoDirectory {
    param (
        [string]$sourceDir,
        [string]$targetDir 
    )
 
    # 遍历所有文件
    Get-ChildItem -LiteralPath $sourceDir -File -Recurse | ForEach-Object {
        $sourceFile = $_.FullName
        $relativePath = $sourceFile.Substring($sourceDir.Length).TrimStart("\")
        $targetFile = Join-Path -Path $targetDir -ChildPath $relativePath
   
        $mediaInfo = Get-MediaInfo -Path $sourceFile
        $fileType = $mediaInfo.Type
       
        if ($fileType -eq "image" -or $fileType -eq "video") { 
            # 转换目标文件名为 .info.json
            $targetFile = $targetFile -replace "\.[^.]+$", ".info.json" 
            Write-LogMessage -message "extract $fileType info: $targetFile" 
            
            if (Test-Path -LiteralPath $targetFile) { Remove-Item -LiteralPath $targetFile }
            
            # 使用 ffprobe 完整导出视频和图片的流/格式信息为 JSON
            $probeOutput = ffprobe -v quiet -print_format json -show_format -show_streams "$sourceFile" 2>$null
            if (-not [string]::IsNullOrWhiteSpace($probeOutput)) {
                # 写入到同名源文件在 targetDir 下对应的 .info.json 中
                $probeOutput | Out-File -LiteralPath $targetFile -Encoding utf8
            } else {
                Write-LogMessage -message "[Warn] ffprobe return empty for: $sourceFile" 
            }
        }
        else {
            Write-LogMessage -message "hard link non-media: $targetFile" 
            if (Test-Path -LiteralPath $targetFile) { Remove-Item -LiteralPath $targetFile }
            New-Item -ItemType HardLink -Path $targetFile -Target $sourceFile | Out-Null
        }
    }
}

Start-InfoTask

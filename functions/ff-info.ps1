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
    Init-Log  ( $runtime.TargetDirName + ".log"  )
    
    # 先创建所有目录
    Create-Directories -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir
    $startTime = Get-Date
    Process-InfoDirectory -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir
    Log-Message -message "Info extraction cost $(((Get-Date) - $startTime).TotalSeconds) Seconds"
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
            Log-Message -message "extract $fileType info: $targetFile" 
            
            if (Test-Path -LiteralPath $targetFile) { Remove-Item -LiteralPath $targetFile }
            
            # 使用 ffprobe 完整导出视频和图片的流/格式信息为 JSON
            $probeOutput = ffprobe -v quiet -print_format json -show_format -show_streams "$sourceFile" 2>$null
            if (-not [string]::IsNullOrWhiteSpace($probeOutput)) {
                # 写入到同名源文件在 targetDir 下对应的 .info.json 中
                $probeOutput | Out-File -LiteralPath $targetFile -Encoding utf8
            } else {
                Log-Message -message "[Warn] ffprobe return empty for: $sourceFile" 
            }
        }
        else {
            Log-Message -message "hard link non-media: $targetFile" 
            if (Test-Path -LiteralPath $targetFile) { Remove-Item -LiteralPath $targetFile }
            New-Item -ItemType HardLink -Path $targetFile -Target $sourceFile | Out-Null
        }
    }
}

Start-InfoTask

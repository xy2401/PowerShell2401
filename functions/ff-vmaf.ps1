[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$SourceDir,

    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$EncodedDirs,

    [switch]$Vertical
)

function Start-VmafTask {
    # 动态确定一个日志文件名字
    $logFileName = "ff-vmaf_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Init-Log $logFileName

    Log-Message -message "=> [VMAF] 启动源文件参考目录: $SourceDir"
    Log-Message -message "=> [VMAF] 参与测评的压制组: $($EncodedDirs -join ', ')"

    $csvOutput = Join-Path (Get-Location).Path "VMAF_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $pivotHash = [ordered]@{}
    $verticalArray = @()
    
    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        Log-Message -message "[Error] 找不到源目录: $SourceDir" 
        return
    }

    $sourceRoot = (Get-Item -LiteralPath $SourceDir).FullName
    $sourceDirName = Split-Path -Leaf $sourceRoot

    foreach ($encDir in $EncodedDirs) {
        if (-not (Test-Path -LiteralPath $encDir -PathType Container)) {
            Log-Message -message "[Warn] 找不到编码目录，已跳过: $encDir" 
            continue
        }

        $encRoot = (Get-Item -LiteralPath $encDir).FullName
        $encFolderName = Split-Path -Leaf $encRoot

        # 计算并截掉两个文件夹名间的“最大公共前缀”，极致精简列名和日志输出
        $minLen = [math]::Min($sourceDirName.Length, $encFolderName.Length)
        $commonLen = 0
        for ($i = 0; $i -lt $minLen; $i++) {
            if ($sourceDirName[$i] -eq $encFolderName[$i]) {
                $commonLen++
            } else {
                break
            }
        }
        if ($commonLen -gt 0) {
            $shortEncName = $encFolderName.Substring($commonLen)
            # 防止源目录和目标目录完全同名导致截取为空
            if (-not [string]::IsNullOrWhiteSpace($shortEncName)) {
                $encFolderName = $shortEncName
            }
        }

        Get-ChildItem -LiteralPath $sourceRoot -File -Recurse | ForEach-Object {
            $sourceFile = $_.FullName
            
            # 使用现有的 Get-MediaInfo 过滤仅支持图片和视频的文件
            $mediaInfo = Get-MediaInfo -Path $sourceFile
            if ($mediaInfo.Type -ne "image" -and $mediaInfo.Type -ne "video") {
                return # 跳过非媒体文件
            }

            $srcRelativePath = $sourceFile.Substring($sourceRoot.Length).TrimStart("\")
            $relativeDir = Split-Path $srcRelativePath -Parent
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($srcRelativePath)
            
            # 安全拼接：如果仅处于根目录，直接使用根目录避免 Join-Path 空字符串报错
            $targetSearchDir = if (-not [string]::IsNullOrEmpty($relativeDir)) { Join-Path $encRoot $relativeDir } else { $encRoot }

            if (-not (Test-Path -LiteralPath $targetSearchDir -PathType Container)) {
                return
            }

            # 忽略后缀寻找对应文件 (必须使用 -LiteralPath 避免方括号 [] 等特殊字符被当成系统通配符报错被过滤)
            $matchedTargets = Get-ChildItem -LiteralPath $targetSearchDir -File | Where-Object { 
                [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $baseName
            }

            if ($matchedTargets.Count -eq 0) {
                return
            }

            # 默认取匹配到的第一个同名转换后的文件
            $targetFile = $matchedTargets[0].FullName
            
            $srcSize = (Get-Item -LiteralPath $sourceFile).Length
            $tgtSize = (Get-Item -LiteralPath $targetFile).Length
            
            $ratio = "N/A"
            if ($srcSize -gt 0) {
                # 计算压缩率占比
                $ratio = ($tgtSize / $srcSize).ToString("P2")
            }

            Log-Message -message "VMAF 计算中: [$encFolderName] $srcRelativePath ..." 

            # FFmpeg libvmaf 核心对比指令
            # -i 转换后的失真图/视频 -i 高质量源图/视频
            $ffmpegArgs = @(
                "-i", $targetFile,
                "-i", $sourceFile,
                "-filter_complex", "libvmaf",
                "-f", "null", "-"
            )

            $vmafScore = "Error"
            $exe = "ffmpeg"
            # 捕获所有 ffmpeg 打印输出
            $ffmpegOutput = & $exe $ffmpegArgs 2>&1
            
            # 提取最后总分段。一般 ffmpeg 对 vmaf 的终端结算行长得像: "VMAF score: 95.123"
            $vmafLine = $ffmpegOutput | Where-Object { $_ -match "VMAF score: ([\d\.]+)" } | Select-Object -Last 1
            
            if ($null -ne $vmafLine -and $vmafLine -match "VMAF score: ([\d\.]+)") {
                $vmafScore = $matches[1]
                Log-Message -message "  > 目录组: $encFolderName | 原大小: $([math]::Round($srcSize/1KB,2))KB | 新大小: $([math]::Round($tgtSize/1KB,2))KB | 压缩百分比: $ratio | VMAF: $vmafScore" 
            } else {
                Log-Message -message "  > [Warn] 无法解析出该文件的 VMAF 结果" 
            }

            if ($Vertical) {
                # 垂直模式: 每次比对产生独立行，带有固定字段头
                $verticalArray += [PSCustomObject]@{
                    "Group"    = $encFolderName
                    "File"     = $srcRelativePath
                    "Size_Src" = $srcSize
                    "Size_Enc" = $tgtSize
                    "Ratio"    = $ratio
                    "VMAF"     = $vmafScore
                }
            } else {
                if (-not $pivotHash.Contains($srcRelativePath)) {
                    $pivotHash[$srcRelativePath] = [ordered]@{
                        "File"     = $srcRelativePath
                        "Size_Src" = $srcSize
                    }
                }

                # 动态生成带有特定压制组标识的列名 (取消 Group 行，改为动态列扩展的数据透视)
                $pivotHash[$srcRelativePath]["Size ($encFolderName)"]  = $tgtSize
                $pivotHash[$srcRelativePath]["Ratio ($encFolderName)"] = $ratio
                $pivotHash[$srcRelativePath]["VMAF ($encFolderName)"]  = $vmafScore
            }
        }
    }

    $hasResults = $false
    if ($Vertical -and $verticalArray.Count -gt 0) {
        $verticalArray | Export-Csv -Path $csvOutput -NoTypeInformation -Encoding UTF8
        $hasResults = $true
    } elseif (-not $Vertical -and $pivotHash.Count -gt 0) {
        # 转换为对象数组用于生成动态结构体的 CSV
        $results = $pivotHash.Values | ForEach-Object { [PSCustomObject]$_ }
        $results | Export-Csv -Path $csvOutput -NoTypeInformation -Encoding UTF8
        $hasResults = $true
    }

    if ($hasResults) {
        Log-Message -message "==============================================="
        Log-Message -message "VMAF 测试计算完毕! CSV 报表已生成至: $csvOutput" 
    } else {
        Log-Message -message "未能在此次任务中完成任何有效的 VMAF 对比和分析!" 
    }
}

Start-VmafTask

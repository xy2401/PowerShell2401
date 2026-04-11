 
param(
    #========================================================
    # 编码预配置模式 (可覆盖全局):
    #   for   -> 批量网格测试模式 (遍历生成不同参数对比)
    #   fast  -> 快速实时编码模式 (内置 preset=10, crf=35)
    #   pro   -> 个人压制归档模式 (内置 preset=5, crf=32)
    #   ultra -> 高画质慢速编码模式 (内置 preset=4, crf=24)
    #========================================================
    [Parameter(Mandatory = $false)]
    [string]$Profile = "pro",   
    
    #========================================================
    # SVT-AV1 CPU 编码效率预设 
    # 取值范围 0-13。数值越小压制越慢，压缩率也越高；越大越快。
    # - 推荐: 10(最快), 5(偏慢/较小), 4(慢/极小)
    #========================================================
    [Parameter(Mandatory = $false)]
    [string]$preset = "5",
    
    #========================================================
    # CRF 恒定质量因子 (恒定码率)控制视觉画质
    # 取值范围 0-63。数值越小画质越高，体积也越大。
    # - 推荐: 35(能看), 32(较清晰), 24(高画质)
    #========================================================
    [Parameter(Mandatory = $false)]
    [string]$crf = "32"   
)

function Start-SvtEncodingTask {
    $suffix = ".av1_svt" 
    Update-Target -suffix $suffix
    $runtime = $global:GlobalConfig.runtime
    Initialize-Log  ( $runtime.TargetDirName + ".log"  )
    # 先创建所有目录
    New-Directories -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir
    $startTime = Get-Date
    Process-SvtDirectory  -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir
    Write-LogMessage -message "Encode cost $(((Get-Date) - $startTime).TotalSeconds) Seconds"

}

function Start-SvtGridTestTask {
    param (
        [string]$presets = "4,5,7,10",
        [string]$crfs = "10,20,25,30,40,50" ,
        [string]$grains = "0,4,8" 
    )

      
    #  "," 逗号切割 或者 空格切割 
    $presetList = $presets -split '[,\s]+' | ForEach-Object { [int]($_.Trim()) }
    $crfList = $crfs -split '[,\s]+' | ForEach-Object { [int]($_.Trim()) }
    $grainList = $grains -split '[,\s]+' | ForEach-Object { [int]($_.Trim()) }

    # 双重循环
    foreach ($preset in $presetList) {
        foreach ($crf  in  $crfList) {
            foreach ($grain  in  $grainList) {

                $script:SharedArgs['preset'] = $preset
                $script:SharedArgs['crf'] = $crf 
                $script:SharedArgs['grain'] = $grain 

  
                $suffix = "_ffsvt_p$($preset)_c$($crf)_g$($grain)"  
                Update-Target -suffix $suffix
                $runtime = $global:GlobalConfig.runtime 
                Initialize-Log (  $runtime.TargetDirName + ".log"  )
                # 先创建所有目录
                New-Directories -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir
                $startTime = Get-Date
                Process-SvtDirectory  -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir 
                Write-LogMessage -message "Encode cost $(((Get-Date) - $startTime).TotalSeconds) Seconds"
       
            }
        }
    } 

}

function Process-SvtDirectory {
    param (
        [string]$sourceDir,
        [string]$targetDir 
    )
 
    # 遍历所有文件
    Get-ChildItem  -LiteralPath $sourceDir -File -Recurse | ForEach-Object {
        $sourceFile = $_.FullName
        $relativePath = $sourceFile.Substring($sourceDir.Length).TrimStart("\")
        $targetFile = Join-Path -Path $targetDir -ChildPath $relativePath
   
        # 使用 Get-MediaInfo 探测媒体文件属性（只需调用一次 ffprobe）
        $mediaInfo = Get-MediaInfo -Path $sourceFile
        $fileType = $mediaInfo.Type
       
        $action = "encode"
        if ($fileType -eq "image") { 
            $targetFile = $targetFile -replace "\.[^.]+$", ".avif" 
        }
        elseif ($fileType -eq "video") {
            $targetFile = $targetFile -replace "\.[^.]+$", ".mp4" 
        }
        else {
            $action = "hardLink"
        }

        # 检查目标文件是否存在，如果存在则添加编号后缀 (如 .2.mp4, .3.mp4)
        if (Test-Path -LiteralPath $targetFile) {
            $dir = Split-Path -Path $targetFile -Parent
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($targetFile)
            $ext = [System.IO.Path]::GetExtension($targetFile)
            
            $counter = 2
            $newTargetFile = Join-Path -Path $dir -ChildPath "$baseName.$counter$ext"
            while (Test-Path -LiteralPath $newTargetFile) {
                $counter++
                $newTargetFile = Join-Path -Path $dir -ChildPath "$baseName.$counter$ext"
            }
            $targetFile = $newTargetFile
        }

        while ($action -ne "return") {
            switch ($action) {
                "encode" {
                    Write-LogMessage -message "encode $targetFile" 
                    if (Test-Path -LiteralPath $targetFile) { 
                        Remove-Item -LiteralPath $targetFile 
                    }
                    Convert-MediaToSvt -inputFile $sourceFile -outputFile $targetFile -preset $preset -crf $crf -grain $grain
                    $action = "return"
                    if ((Get-Item -LiteralPath $targetFile).Length -eq 0) {
                        $action = "trunc"
                    }
                }
                "trunc" {
                    Write-LogMessage -message  "encode trunc $targetFile" 
                    if (Test-Path -LiteralPath $targetFile) { 
                        Remove-Item -LiteralPath $targetFile 
                    }
                    Convert-MediaToSvt -inputFile $sourceFile -outputFile $targetFile -preset $preset -crf $crf -grain $grain -trunc 1 
                    $action = "return"
                    if ((Get-Item -LiteralPath $targetFile).Length -eq 0) {
                        $action = "hardLink"
                    }
                }
                "hardLink" {
                    Write-LogMessage -message  "hard link  $targetFile" 
                    if (Test-Path -LiteralPath $targetFile) { 
                        Remove-Item -LiteralPath $targetFile 
                    }
                    New-Item -ItemType HardLink -Path $targetFile -Target $sourceFile
                    $action = "return"
                } 
            } 
        } 
    }
}
 
# https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Ffmpeg.md
#ffmpeg -i infile.mkv -c:v libsvtav1 -preset 5 -crf 32 -g 240 -pix_fmt yuv420p10le -svtav1-params tune=0:film-grain=8 -c:a copy outfile.mkv
# Example 1: Fast/Realtime Encoding (fast)
# ffmpeg -i infile.mkv -c:v libsvtav1 -preset 10 -crf 35 -c:a copy outfile.mkv
# Example 2: Encoding for Personal Use (pro)
# ffmpeg -i infile.mkv -c:v libsvtav1 -preset 5 -crf 32 -g 240 -pix_fmt yuv420p10le -svtav1-params tune=0:film-grain=8 -c:a copy outfile.mkv
# Example 3: High Quality Encoding (ultra)
# ffmpeg -i infile.mkv -c:v libsvtav1 -preset 4 -crf 24 -g 240 -pix_fmt yuv420p10le -svtav1-params tune=0:film-grain=8 -c:a copy outfile.mkv
function Convert-MediaToSvt {
    param (
        [string]$inputFile,
        [string]$outputFile,
        [int]$preset = 5,
        [int]$crf = 30,
        [int]$g = 240,
        [int]$grain = 8,
        [int]$trunc = 0
    )
    
 
    $preset = $script:SharedArgs['preset'] ?? $preset
    $crf = $script:SharedArgs['crf'] ?? $crf
    $g = $script:SharedArgs['g'] ?? $g
    $grain = $script:SharedArgs['grain'] ?? $grain
    $trunc = $script:SharedArgs['trunc'] ?? $trunc  

    # 电影颗粒
    $film = "" 
    if (0 -ne $grain ) {
        $film = ":film-grain=$grain" 
    }

    # 参数数组 (核心编码参数)
    $ffmpegParams = @(
        "-c:v", "libsvtav1",
        "-preset", $preset,
        "-crf", $crf,
        "-g", $g,
        "-pix_fmt", "yuv420p10le",
        "-svtav1-params", "tune=0$film",
        "-c:a", "copy"
    )

    if ($null -ne $script:ffArgs.report) {
        $ffmpegParams += "-report"
    }
   
    if (0 -ne $trunc ) {
        $ffmpegParams += "-filter:v"
        $ffmpegParams += "crop=trunc(in_w/2)*2:trunc(in_h/2)*2:0:out_h"
    }
         
    $exe = "ffmpeg" 
    # 构造完整参数列表
    $allArgs = @()
    $allArgs += "-i"
    $allArgs += $inputFile
    $allArgs += $ffmpegParams
    $allArgs += $outputFile
    $allArgs += "-y" # 默认覆盖

    Write-LogMessage -message "Executing: $exe $($allArgs -join ' ')"

    $runtime = $global:GlobalConfig.runtime  
    if ($runtime.IsDebug -and $null -ne $runtime.LogFilePath) {
        & $exe $allArgs 2>&1 | Tee-Object -FilePath $runtime.LogFilePath -Append
    }
    else {
        & $exe $allArgs
    }
}

# 存入脚本级变量
$script:SharedArgs = $PSBoundParameters ?? $PSBoundParameters.Clone() ?? @{}
 
# ========================================================
# Profile 预设配置字典 (利用哈希表对象取代冗长的 switch case)
# ========================================================
$profileConfigs = @{
    "fast"  = @{ preset = 10; crf = 35; desc = "快速编码模式" }
    "ultra" = @{ preset = 5; crf = 24; desc = "高质量慢速压制模式" }
    "pro"   = @{ preset = 5; crf = 32; desc = "个人日常归档模式" }
}

$currentProfile = $Profile.ToLower()

if ($currentProfile -eq "for") {
    Write-LogMessage -message "=> [Profile: for] 调用 Start-SvtGridTestTask 参数遍历生成"
    Start-SvtGridTestTask
} 
else {
    # 获取预设对象，找不到对应配置则自动兜底回到 fallback(pro)
    $config = $profileConfigs[$currentProfile]
    if ($null -eq $config) {
        $config = $profileConfigs["pro"]
        $currentProfile = "default(pro)"
    }

    # 命令行传参优先级最高：如果未显式通过命令行提供该参数（不在 PSBoundParameters 中），才使用 Profile 模板对象的预设覆盖
    if (-not $PSBoundParameters.ContainsKey('preset')) {
        $script:SharedArgs['preset'] = $config.preset
    }
    if (-not $PSBoundParameters.ContainsKey('crf')) {
        $script:SharedArgs['crf'] = $config.crf
    }

    # 读取最终敲定的参数，用于日志播报
    $finalPreset = $script:SharedArgs['preset'] ?? $preset
    $finalCrf = $script:SharedArgs['crf'] ?? $crf
    
    Write-LogMessage -message "=> [Profile: $currentProfile] $($config.desc) (实际下发配置: preset=$finalPreset, crf=$finalCrf)"
    
    Start-SvtEncodingTask 
}







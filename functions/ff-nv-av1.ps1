param(
    #========================================================
    # 编码预配置模式 (可覆盖全局):
    #   for   -> 批量网格测试模式 (遍历生成不同参数对比)
    #   fast  -> 快速实时编码模式 (内置 preset=p1, cq=35)
    #   pro   -> 个人压制归档模式 (内置 preset=p4, cq=32)
    #   ultra -> 高画质慢速编码模式 (内置 preset=p7, cq=24)
    #========================================================
    [Parameter(Mandatory = $false)]
    [string]$Profile = "pro",   
    
    #========================================================
    # NVENC-AV1 硬件编码效率预设 
    # 取值范围 p1-p7。数值越小(p1)压制越快且压缩率较低；越大(p7)越慢但质量压缩率最好。
    # - 推荐: p1(最快), p4(默认/均衡), p7(最高效质量)
    #========================================================
    [Parameter(Mandatory = $false)]
    [string]$preset = "p4",
    
    #========================================================
    # CQ 恒定质量模式控制视觉画质 (NVENC VBR)
    # 取值范围 0-63 (0为自动)。数值越小画质越高，体积也越大。
    # - 推荐: 35(能看), 32(较清晰), 24(高画质)
    #========================================================
    [Parameter(Mandatory = $false)]
    [string]$cq = "32"   
)

function Start-NvEncodingTask {
    $suffix = ".av1_nvenc" 
    Update-Target -suffix $suffix
    $runtime = $global:GlobalConfig.runtime
    Initialize-Log  ( $runtime.TargetDirName + ".log"  )
    # 先创建所有目录
    New-Directories -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir
    $startTime = Get-Date
    Process-NvDirectory  -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir
    Write-LogMessage -message "Encode cost $(((Get-Date) - $startTime).TotalSeconds) Seconds"
}

function Start-NvGridTestTask {
    param (
        [string]$presets = "p1,p4,p7",
        [string]$cqs = "20,25,30,35" 
    )
      
    # ',' 逗号切割 或者 空格切割 
    $presetList = $presets -split '[,\s]+' | ForEach-Object { $_.Trim() }
    $cqList = $cqs -split '[,\s]+' | ForEach-Object { [int]($_.Trim()) }

    # 双重循环
    foreach ($preset in $presetList) {
        foreach ($cq in $cqList) {
            $script:SharedArgs['preset'] = $preset
            $script:SharedArgs['cq'] = $cq 
  
            $suffix = "_ffnv_$($preset)_cq$($cq)"  
            Update-Target -suffix $suffix
            $runtime = $global:GlobalConfig.runtime 
            Initialize-Log ( $runtime.TargetDirName + ".log" )
            # 先创建所有目录
            New-Directories -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir
            $startTime = Get-Date
            Process-NvDirectory -sourceDir $runtime.WorkDir -targetDir $runtime.TargetDir 
            Write-LogMessage -message "Encode cost $(((Get-Date) - $startTime).TotalSeconds) Seconds"
        }
    } 
}

function Process-NvDirectory {
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
                    if (Test-Path -LiteralPath $targetFile) { Remove-Item -LiteralPath $targetFile }
                    Convert-MediaToNv -inputFile $sourceFile -outputFile $targetFile -inWidth $mediaInfo.Width -inHeight $mediaInfo.Height
                    $action = "return"
                    if ((Get-Item -LiteralPath $targetFile).Length -eq 0) {
                        $action = "trunc"
                    }
                }
                "trunc" {
                    Write-LogMessage -message "encode trunc $targetFile" 
                    if (Test-Path -LiteralPath $targetFile) { Remove-Item -LiteralPath $targetFile }
                    Convert-MediaToNv -inputFile $sourceFile -outputFile $targetFile -trunc 1 -inWidth $mediaInfo.Width -inHeight $mediaInfo.Height
                    $action = "return"
                    if ((Get-Item -LiteralPath $targetFile).Length -eq 0) {
                        $action = "hardLink"
                    }
                }
                "hardLink" {
                    Write-LogMessage -message "hard link $targetFile" 
                    if (Test-Path -LiteralPath $targetFile) { Remove-Item -LiteralPath $targetFile }
                    New-Item -ItemType HardLink -Path $targetFile -Target $sourceFile | Out-Null
                    $action = "return"
                } 
            } 
        } 
    }
}

function Convert-MediaToNv {
    param (
        [string]$inputFile,
        [string]$outputFile,
        [int]$inWidth = 0,
        [int]$inHeight = 0,
        [string]$preset = "p4",
        [int]$cq = 32,
        [int]$trunc = 0
    )
    
    $preset = $script:SharedArgs['preset'] ?? $preset
    $cq = $script:SharedArgs['cq'] ?? $cq
    $trunc = $script:SharedArgs['trunc'] ?? $trunc  

    # 参数数组 (核心编码参数, 针对 NVENC-AV1)
    $ffmpegParams = @(
        "-c:v", "av1_nvenc",
        "-preset", $preset,
        "-rc", "vbr",
        "-cq", $cq,
        "-pix_fmt", "p010le",
        "-c:a", "copy"
    )

    if ($null -ne $script:ffArgs.report) {
        $ffmpegParams += "-report"
    }
   
    $vfFilters = @()
    $maxRes = $global:GlobalConfig.nvenc.max_resolution
    if ($null -ne $maxRes -and $maxRes -gt 0) {
        if ($inWidth -gt $maxRes -or $inHeight -gt $maxRes) {
            Write-LogMessage -message "Origin resolution ${inWidth}x${inHeight} exceeds NVENC limit $maxRes, scaling down to fit." -Level Warning
            $vfFilters += "scale=${maxRes}:${maxRes}:force_original_aspect_ratio=decrease"
        } elseif ($inWidth -le 0 -or $inHeight -le 0) {
            # fallback safety auto scale
            $vfFilters += "scale=${maxRes}:${maxRes}:force_original_aspect_ratio=decrease"
        }
    }

    if (0 -ne $trunc ) {
        $vfFilters += "crop=trunc(in_w/2)*2:trunc(in_h/2)*2:0:out_h"
    }

    if ($vfFilters.Count -gt 0) {
        $ffmpegParams += "-filter:v"
        $ffmpegParams += ($vfFilters -join ",")
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
    "fast"  = @{ preset = "p1"; cq = 35; desc = "快速硬件编码模式" }
    "ultra" = @{ preset = "p7"; cq = 24; desc = "高质量慢速硬件压制模式" }
    "pro"   = @{ preset = "p4"; cq = 32; desc = "个人日常归档模式" }
}

$currentProfile = $Profile.ToLower()

if ($currentProfile -eq "for") {
    Write-LogMessage -message "=> [Profile: for] 调用 Start-NvGridTestTask 硬件参数遍历生成"
    Start-NvGridTestTask
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
    if (-not $PSBoundParameters.ContainsKey('cq')) {
        $script:SharedArgs['cq'] = $config.cq
    }

    # 读取最终敲定的参数，用于日志播报
    $finalPreset = $script:SharedArgs['preset'] ?? $preset
    $finalCq = $script:SharedArgs['cq'] ?? $cq
    
    Write-LogMessage -message "=> [Profile: $currentProfile] $($config.desc) (NVENC 实际下发配置: preset=$finalPreset, cq=$finalCq)"
    
    Start-NvEncodingTask 
}

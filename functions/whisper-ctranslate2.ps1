<#
.SYNOPSIS
    使用 whisper-ctranslate2 批量为视频生成字幕。

.DESCRIPTION
    该脚本会扫描指定目录下的视频文件，并调用 whisper-ctranslate2 CLI 生成字幕。
    支持自动检测语言，也可手动指定。

.PARAMETER Path
    目标文件夹路径，默认为当前目录。

.PARAMETER Depth
    处理路径的深度。默认 0 即处理当前目录下的文件，1 表示处理一级子文件夹内的文件。

.PARAMETER Language
    指定语言代码（如 zh, ja, en）。如果不指定，将自动检测。

.PARAMETER Model
    使用的模型名称。默认 turbo。

.PARAMETER Device
    计算设备。默认 cuda。

.PARAMETER ComputeType
    计算精度。默认 float16。

.PARAMETER OutputFormat
    字幕输出格式。默认 srt。
#>

[CmdletBinding(PositionalBinding = $false)]
param(
 
    [Parameter(HelpMessage = "处理路径的深度。默认 0 即处理当前目录下的文件。")]
    [int]$Depth = 0,

    [Parameter(HelpMessage = "语言代码 (常用: zh, ja, en, ko)。留空则自动检测。")]
    [string]$Language = $null,

    [Parameter(HelpMessage = "模型大小或名称")]
    [string]$Model = "turbo",

    [Parameter(HelpMessage = "计算设备")]
    [string]$Device = "cuda",

    [Parameter(HelpMessage = "计算类型")]
    [string]$ComputeType = "float16",

    [Parameter(HelpMessage = "字幕输出格式 (如 srt, vtt, txt, tsv, json, all)。默认 srt")]
    [string]$OutputFormat = "srt"
)

$runtime = $global:GlobalConfig.runtime
$Path = $runtime.WorkDir
 

# 动态确定一个日志文件名字
$logFileName = "whisper-ct2_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Init-Log $logFileName

# 语言代码校验
if (-not [string]::IsNullOrWhiteSpace($Language)) {
    $validLanguages = @(
        "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo", "br", "bs", "ca", "cs", "cy", "da", "de", "el", "en", "es", "et", "eu", "fa", "fi", "fo", "fr", "gl", "gu", "ha", "haw", "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja", "jw", "ka", "kk", "km", "kn", "ko", "la", "lb", "ln", "lo", "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt", "my", "ne", "nl", "nn", "no", "oc", "pa", "pl", "ps", "pt", "ro", "ru", "sa", "sd", "si", "sk", "sl", "sn", "so", "sq", "sr", "su", "sv", "sw", "ta", "te", "tg", "th", "tk", "tl", "tr", "tt", "uk", "ur", "uz", "vi", "yi", "yo", "zh", "yue"
    )
    if ($validLanguages -notcontains $Language) {
        Log-Message -message "[Error] 非法的语言代码: '$Language'。请使用正确的代码（如 日语为 'ja', 中文为 'zh'）。" -Level Error
        return
    }
}

# 设置环境变量以获得更详细的实时日志
$env:PYTHONUNBUFFERED = "1"
$env:CT2_VERBOSE = 1

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Log-Message -message "[Error] 找不到目标目录: $Path"
    return
}

# 严格锁定处理只在指定的精确深度级产生
$targetDirs = Get-Directory-Depth -Path $Path -Depth $Depth

Log-Message -message "=> [Whisper-CT2] 开始处理视频字幕生成，共选中 $($targetDirs.Count) 个目录"

foreach ($dir in $targetDirs) {
    $dirFullName = $dir.FullName
    Log-Message -message "-----------------------------------------------"
    Log-Message -message "正在处理目录: $dirFullName"

    $files = Get-ChildItem -LiteralPath $dirFullName -File
    $processedCount = 0

    foreach ($file in $files) {
        $type = Get-FileType -FileName $file.Name
        if ($type -ne "video") { continue }

        Log-Message -message ">>> 正在处理视频: $($file.Name)"
        
        # 构建命令参数 (适配 whisper-ctranslate2)
        $args = @()
        $args += "`"$($file.FullName)`""
        $args += "--model"
        $args += $Model
        $args += "--device"
        $args += $Device
        $args += "--compute_type"
        $args += $ComputeType
        $args += "--output_dir"
        $args += "`"$dirFullName`""
        $args += "--output_format"
        $args += $OutputFormat
        $args += "--vad_filter"
        $args += "True"
        $args += "--word_timestamps"
        $args += "True"

        if (-not [string]::IsNullOrWhiteSpace($Language)) {
            $args += "--language"
            $args += $Language
            Log-Message -message " [+] 已指定语言: $Language"
        }
        else {
            Log-Message -message " [!] 未指定语言，将自动检测"
        }

        # 执行命令
        $cmdStr = "whisper-ctranslate2 " + ($args -join " ")
        Log-Message -message " [Command] $cmdStr"

        try {
            $processArgs = $args -join " "
            Invoke-Expression "whisper-ctranslate2 $processArgs"
            
            if ($LASTEXITCODE -eq 0) {
                Log-Message -message " [Success] 字幕生成成功: $($file.Name)" -Level Success
                $processedCount++
            }
            else {
                Log-Message -message " [Error] whisper-ctranslate2 返回退出码: $LASTEXITCODE" -Level Error
            }
        }
        catch {
            Log-Message -message " [Error] 执行过程中出现异常: $_" -Level Error
        }
    }

    Log-Message -message " 状态: 该目录处理完毕，共生成 $processedCount 个字幕文件。"
}

Log-Message -message "=> [Whisper-CT2] 全部任务处理完成！"

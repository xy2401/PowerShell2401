<#
.SYNOPSIS
    使用 faster-whisper 批量为视频生成字幕。

.DESCRIPTION
    该脚本会扫描指定目录下的视频文件，并调用 faster-whisper-cli 生成字幕。
    支持自动检测语言，也可手动指定。

.PARAMETER Path
    目标文件夹路径，默认为当前目录。

.PARAMETER Depth
    处理路径的深度。默认 0 即处理当前目录下的文件，1 表示处理一级子文件夹内的文件。

.PARAMETER Language
    指定语言代码（如 zh, ja, en）。如果不指定，whisper 将自动检测。

.PARAMETER Model
    使用的模型名称。默认 turbo。

.PARAMETER Device
    计算设备。默认 cuda。

.PARAMETER ComputeType
    计算精度。默认 float16。
#>

[CmdletBinding(PositionalBinding = $false)]
param( 

    [Parameter(HelpMessage = "处理路径的深度。默认 0 即处理当前目录下的文件。")]
    [int]$Depth = 0,

    [Parameter(HelpMessage = "语言代码 (常用: zh, ja, en, ko)。留空则自动检测。")]
    [string]$Language = $null,

    [Parameter(HelpMessage = "模型大小或路径")]
    [string]$Model = "turbo",

    [Parameter(HelpMessage = "计算设备")]
    [string]$Device = "cuda",

    [Parameter(HelpMessage = "计算类型")]
    [string]$ComputeType = "float16"
 
)

$runtime = $global:GlobalConfig.runtime
$Path = $runtime.WorkDir
 

# 动态确定一个日志文件名字
$logFileName = "faster-whisper_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

# 设置环境变量以获得更详细的实时日志 (由 Python 的 logging 模块控制)
$env:PYTHONUNBUFFERED = "1"
$env:CT2_VERBOSE = 1

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Log-Message -message "[Error] 找不到目标目录: $Path"
    return
}

# 严格锁定处理只在指定的精确深度级产生 (复用精确寻层逻辑)
$targetDirs = Get-Directory-Depth -Path $Path -Depth $Depth

Log-Message -message "=> [Faster-Whisper] 开始处理视频字幕生成，共选中 $($targetDirs.Count) 个目录"

foreach ($dir in $targetDirs) {
    $dirFullName = $dir.FullName
    Log-Message -message "-----------------------------------------------"
    Log-Message -message "正在处理目录: $dirFullName"

    # 获取该目录下的视频文件
    $files = Get-ChildItem -LiteralPath $dirFullName -File
    $processedCount = 0

    foreach ($file in $files) {
        $type = Get-FileType -FileName $file.Name
        if ($type -ne "video") { continue }

        Log-Message -message ">>> 正在处理视频: $($file.Name)"
        
        # 构建命令参数
        $args = @()
        $args += "`"$($file.FullName)`""
        $args += "--model_size_or_path"
        $args += $Model
        $args += "--device"
        $args += $Device
        $args += "--compute_type"
        $args += $ComputeType
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
            Log-Message -message " [!] 未指定语言，将由 Whisper 自动检测"
        }

        # 构建最终命令字符串以进行日志记录
        $cmdStr = "faster-whisper " + ($args -join " ")
        Log-Message -message " [Command] $cmdStr"

        try {
            # 使用 Start-Process 或直接运行以捕获实时输出
            # 这里选择直接运行，以便在当前控制台看到输出
            $processArgs = $args -join " "
            Invoke-Expression "faster-whisper $processArgs"
            
            if ($LASTEXITCODE -eq 0) {
                Log-Message -message " [Success] 字幕生成成功: $($file.Name)" -Level Success
                $processedCount++
            }
            else {
                Log-Message -message " [Error] faster-whisper 返回退出码: $LASTEXITCODE" -Level Error
            }
        }
        catch {
            Log-Message -message " [Error] 执行过程中出现异常: $_" -Level Error
        }
    }

    Log-Message -message " 状态: 该目录处理完毕，共生成 $processedCount 个字幕文件。"
}

Log-Message -message "=> [Faster-Whisper] 全部任务处理完成！"

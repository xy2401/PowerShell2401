# Log module

<#
.SYNOPSIS
    初始化日志系统，设置日志文件路径。
#>
function Initialize-Log {
    param (
        [string]$LogFile
    )

    $runtime = $global:GlobalConfig.runtime

    # 如果没有指定日志文件，则使用默认的 .debug.log 文件名
    if ([string]::IsNullOrWhiteSpace($LogFile)) {
        $LogFile = "$($runtime.WorkDirName).debug.log"
    }

   
    # 统一拼接到父级目录
    $runtime.LogFilePath = Join-Path $runtime.ParentDir $LogFile
    
    Write-Host "[LOG INIT] LogFile: $($runtime.LogFilePath)" -ForegroundColor Gray

}

<#
.SYNOPSIS
    统一的日志记录函数。如果初始化了路径，则写入文件。
#>
function Write-LogMessage {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info',
        
        # 允许输出绝对的纯净日志，不附带任何时间戳和级别前缀，就像调用原生的 Write-Host
        [switch]$NoPrefix,
        
        # 用户完全自定义的前景色设定（优先级高于内置的 Level 系统色）
        [System.ConsoleColor]$ForegroundColor,
        
        # 用户自定义的背景色设定
        [System.ConsoleColor]$BackgroundColor,
        
        # 是否不打印末尾换行符
        [switch]$NoNewline
    )

    # 计算内置前景色
    $defaultColor = switch ($Level) {
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
        default { 'Cyan' }
    }
    
    # 用户颜色覆盖权
    $fgColor = if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $ForegroundColor } else { $defaultColor }

    # 根据前缀模式格式化
    if ($NoPrefix) {
        $logEntry = $Message
    } else {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logEntry = "[$timestamp] [$($Level.ToUpper())] $Message"
    }
    
    # 始终输出到控制台
    $writeHostArgs = @{
        Object = $logEntry
        ForegroundColor = $fgColor
    }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) {
        $writeHostArgs.BackgroundColor = $BackgroundColor
    }
    if ($PSBoundParameters.ContainsKey('NoNewline') -and $NoNewline) {
        $writeHostArgs.NoNewline = $true
    }
    
    Write-Host @writeHostArgs

    $runtime = $global:GlobalConfig.runtime

    # 只有开启了调试模式且设置了路径，才写入文件
    if ($runtime.IsDebug -and $null -ne $runtime.LogFilePath) {
        $logEntry | Out-File -LiteralPath $runtime.LogFilePath -Append -Encoding utf8
    }
}

Export-ModuleMember -Function Write-LogMessage, Initialize-Log

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
        [string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
        default { 'Cyan' }
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$($Level.ToUpper())] $Message"
    
    # 始终输出到控制台
    Write-Host $logEntry -ForegroundColor $color


    $runtime = $global:GlobalConfig.runtime


    # 只有开启了调试模式且设置了路径，才写入文件
    if ($runtime.IsDebug -and $null -ne $runtime.LogFilePath) {
        $logEntry | Out-File -LiteralPath $runtime.LogFilePath -Append -Encoding utf8
    }
}

Export-ModuleMember -Function Write-LogMessage, Initialize-Log

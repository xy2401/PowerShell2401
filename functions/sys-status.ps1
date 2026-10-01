<#
.SYNOPSIS
    演示如何使用共享日志函数展示系统状态。

.DESCRIPTION
    输出当前计算机名、用户名以及日志模块的基本运行状态，用于快速确认 pw2401 已正确加载。

.EXAMPLE
    # ExampleId: runtime-status
    pw2401 status

    显示当前会话的基础状态。

.NOTES
    Requires: PowerShell
#>

Write-LogMessage "正在获取系统状态..." -Level Info
Write-LogMessage -NoPrefix "计算机名: $env:COMPUTERNAME" -ForegroundColor Yellow
Write-LogMessage -NoPrefix "当前用户: $env:USERNAME" -ForegroundColor Cyan
Write-LogMessage "状态获取成功！" -Level Success

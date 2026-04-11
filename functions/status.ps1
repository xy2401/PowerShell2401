<#
.SYNOPSIS
    演示如何使用共享日志函数展示系统状态。
#>

Write-LogMessage "正在获取系统状态..." -Level Info
Write-Host "计算机名: $env:COMPUTERNAME" -ForegroundColor Yellow
Write-Host "当前用户: $env:USERNAME" -ForegroundColor Cyan
Write-LogMessage "状态获取成功！" -Level Success

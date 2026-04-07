<#
.SYNOPSIS
    显示所有系统命令。
#>
param()

$FunctionFolder = $PSScriptRoot

# 获取由 [CmdletBinding()] 引入的系统内置通用参数 (确保是字符串数组)
$CommonParams = [string[]]((Get-Command "$PSScriptRoot\debug-CmdletBinding.ps1").Parameters.Keys)

function Format-HelpItem {
    Param($File, $Color)
    $help = Get-Help $File.FullName
    $cmd = Get-Command $File.FullName
    
    $allParams = $cmd.Parameters.Values
    # 使用 $script: 作用域访问脚本级变量
    $sysParams = $allParams | Where-Object { $script:CommonParams -contains $_.Name } | ForEach-Object { "-$($_.Name)" }
    $customParams = $allParams | Where-Object { $script:CommonParams -notcontains $_.Name } | ForEach-Object { "-$($_.Name)" }

    Write-Host " - $($File.BaseName)" -ForegroundColor $Color
    Write-Host "   [CmdletBinding()] $($sysParams -join ' ')" -ForegroundColor Gray
    Write-Host "   [参数] $($customParams -join ' ')" -ForegroundColor Gray
    if ($help.Synopsis) { Write-Host "   说明: $($help.Synopsis -replace '`r|`n', ' ')" }
}

Write-Host "`n================ Powershell2401 工具箱帮助中心 ================" -ForegroundColor Cyan
Write-Host "用法: Powershell2401 <命令名> [参数]`n" -ForegroundColor Gray

Write-Host "[ 系统命令 (functions 目录) ]" -ForegroundColor Yellow
if (Test-Path -LiteralPath $FunctionFolder) {
    Get-ChildItem -LiteralPath $FunctionFolder -Filter *.ps1 | ForEach-Object { Format-HelpItem $_ "Cyan" }
}

Write-Host "======================================================`n"

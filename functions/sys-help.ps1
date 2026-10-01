<#
.SYNOPSIS
    显示所有系统命令。

.DESCRIPTION
    扫描 functions 目录，并根据每个脚本的 PowerShell 注释帮助显示命令、参数和简要说明。

.EXAMPLE
    # ExampleId: command-list
    pw2401 help

    显示当前安装中可用的全部命令。

.NOTES
    Requires: PowerShell
#>
param()

$FunctionFolder = $PSScriptRoot

# 获取由 [CmdletBinding()] 引入的系统内置通用参数 (确保是字符串数组)
$CommonParams = [string[]]((Get-Command "$PSScriptRoot\sys-debug-CmdletBinding.ps1").Parameters.Keys)

function Format-HelpItem {
    Param($File, $Color)
    $help = Get-Help $File.FullName
    $cmd = Get-Command $File.FullName
    
    $allParams = $cmd.Parameters.Values
    # 使用 $script: 作用域访问脚本级变量
    $sysParams = $allParams | Where-Object { $script:CommonParams -contains $_.Name } | ForEach-Object { "-$($_.Name)" }
    $customParams = $allParams | Where-Object { $script:CommonParams -notcontains $_.Name } | ForEach-Object { "-$($_.Name)" }

    Write-LogMessage -NoPrefix " - $($File.BaseName)" -ForegroundColor $Color
    Write-LogMessage -NoPrefix "   [CmdletBinding()] $($sysParams -join ' ')" -ForegroundColor Gray
    Write-LogMessage -NoPrefix "   [参数] $($customParams -join ' ')" -ForegroundColor Gray
    if ($help.Synopsis) { Write-LogMessage -NoPrefix "   说明: $($help.Synopsis -replace '`r|`n', ' ')" }
}

Write-LogMessage -NoPrefix "`n================ Powershell2401 工具箱帮助中心 ================" -ForegroundColor Cyan
Write-LogMessage -NoPrefix "用法: Powershell2401 <命令名> [参数]`n" -ForegroundColor Gray

if ($null -ne $global:Pw2401CommandAliases) {
    Write-LogMessage -NoPrefix "[ 兼容别名 ]" -ForegroundColor Yellow
    $global:Pw2401CommandAliases.GetEnumerator() | Sort-Object Key | ForEach-Object {
        Write-LogMessage -NoPrefix " - $($_.Key) -> $($_.Value)" -ForegroundColor Gray
    }
    Write-LogMessage -NoPrefix "`n"
}

Write-LogMessage -NoPrefix "[ 系统命令 (functions 目录) ]" -ForegroundColor Yellow
if (Test-Path -LiteralPath $FunctionFolder) {
    Get-ChildItem -LiteralPath $FunctionFolder -Filter *.ps1 | ForEach-Object { Format-HelpItem $_ "Cyan" }
}

Write-LogMessage -NoPrefix "======================================================`n"

# # 0. Params
# param(
#     [Parameter(Mandatory = $false, Position = 0)]
#     [string]$Action,
#     # 使用 DontShow 隐藏参数，并确保类型 [string] 在后
#     [Parameter(DontShow = $true)]
#     [string]$ActionHidden,
#     # 收集剩余参数以透明转发
#     [Parameter(ValueFromRemainingArguments = $true)]
#     $RemainingArguments
# )
# # 如果 $RemainingArguments 为 $null，则赋值为 @()；否则保持原值
# $RemainingArguments ??= @()


$Action = $null
$RemainingArguments = @()
if ($args.Count -gt 0) {
    # 严格按照位置取值：强行把第一个敲下的单词当做 Action
    $Action = $args[0]
}
if ($args.Count -gt 1) {
    # 将身后剩下的所有单词收集起来透明转发
    $RemainingArguments = @($args[1..($args.Count - 1)])
}




# 1. 环境初始化
$ProjectFunctions = Join-Path $PSScriptRoot "functions"

 
Get-ChildItem "$PSScriptRoot\lib\*.psm1" | ForEach-Object { Import-Module $_.FullName -Force }

 
# 全局变量
$global:GlobalConfig = Get-GlobalConfig -ProjectRoot $PSScriptRoot -Arguments $RemainingArguments
 

 
Init-Log

  
Log-Message "Action:`n$Action" -Level Info
Log-Message "RemainingArguments:`n$RemainingArguments" -Level Info

 
if ([string]::IsNullOrWhiteSpace($Action)) {
    # 情况 A: 未提供动作参数，默认执行 help
    Log-Message "未提供动作参数，默认执行 help"
    $Action = "help" 
}
elseif (-not (Test-Path (Join-Path $ProjectFunctions "$Action.ps1"))) {
    # 情况 B: 提供了动作但文件不存在，记录警告并重定向到 help
    Log-Message "未识别的命令: $Action" -Level Warning
    $Action = "help" 
}
  
$TargetFile = Join-Path $ProjectFunctions "$Action.ps1"

 
# 3. 最终执行
& $TargetFile @RemainingArguments 

# 将所有剩余参数拼接回一行纯命令字符串
# $argsString = $RemainingArguments -join ' '
# 使用 Invoke-Expression 让 PowerShell 的引擎就像是在键盘前重新敲击这行命令一样，重新触发一遍所有的 `-Name` 等参数前缀的判定
# Invoke-Expression ". `"$TargetFile`" $argsString"

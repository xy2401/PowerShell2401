[CmdletBinding(PositionalBinding = $false)]
param(
    # 测试字符串类型
    [Parameter(Mandatory = $false)]
    [string]$TestString,

    # 测试数字类型
    [Parameter(Mandatory = $false)]
    [int]$TestInt,

    # 测试开关类型
    [Parameter(Mandatory = $false)]
    [switch]$TestSwitch,

    # 收集剩余参数以透明转发
    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArguments
)

Log-Message '------ [Debug Log] 开启传入参数测试 ------' -Level Info

# 遍历并打印所有成功捕获的具名参数
foreach ($key in $PSBoundParameters.Keys) {
    if ($key -ne 'RemainingArguments') {
        Log-Message "捕获到具名参数: [$key] = $($PSBoundParameters[$key])" -Level Info
    }
}

# 打印没有被捕获进具名参数的剩余流浪参数
Log-Message "未捕获的剩余参数 ($($RemainingArguments.Count) 个): [$($RemainingArguments -join ', ')]" -Level Info

# 打印配置项
$runtimeJson = $GlobalConfig.runtime | ConvertTo-Json  
Log-Message "当前 Runtime 配置详情:`n$runtimeJson" -Level Info

Log-Message '------ [Debug Log] 脚本执行完毕 ------' -Level Success


# 在脚本逻辑中
Write-Host "已绑定的具名参数:"
$PSBoundParameters.GetEnumerator() | ForEach-Object {
    Write-Host "$($_.Key) = $($_.Value)"
}


# 存入脚本级变量
$script:SharedArgs = $PSBoundParameters ?? $PSBoundParameters.Clone() ?? @{}

# ==========================================
# 演示区：函数内部的参数获取方式
# ==========================================

function Test-InnerFunction {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TestString,

        [Parameter(Mandatory = $false)]
        [int]$TestInt,

        [Parameter(Mandatory = $false)]
        [switch]$TestSwitch
    )

    Write-Host "`n[内部函数 Test-InnerFunction] 侦测结果:" -ForegroundColor Cyan
    
    # 查看函数自身的 PSBoundParameters
    Write-Host "  -> 函数内部自己的 `$PSBoundParameters:" -ForegroundColor Green
    if ($PSBoundParameters.Count -gt 0) {
        $PSBoundParameters.GetEnumerator() | ForEach-Object {
            Write-Host "       $($_.Key) = $($_.Value)"
        }
    }
    else {
        Write-Host "       (空 - 没有绑定任何参数)" -ForegroundColor DarkGray
    }

    # 查看外部共享的 script:SharedArgs (来自外部父作用域)
    Write-Host "  -> 从外部读取的 `$script:SharedArgs:" -ForegroundColor Yellow
    if ($script:SharedArgs.Count -gt 0) {
        $script:SharedArgs.GetEnumerator() | ForEach-Object {
            Write-Host "       $($_.Key) = $($_.Value)"
        }
    }
    else {
        Write-Host "       (空)" -ForegroundColor DarkGray
    }
}

Write-Host "`n>>> 演示 1: 直接调用内部函数 (不额外传递参数) <<<" -ForegroundColor Magenta
Test-InnerFunction

Write-Host "`n>>> 演示 2: 使用 @script:SharedArgs 参数转发(Splatting)调用内部函数 <<<" -ForegroundColor Magenta
Test-InnerFunction -TestString $TestString



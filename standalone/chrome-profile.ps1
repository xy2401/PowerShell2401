#Requires -Version 7.0

<#
.SYNOPSIS
    启动独立 Chrome 实例，保存启动参数、环境变量和程序路径。

.DESCRIPTION
    首个参数为实例名（字母、数字、下划线或连字符，不能以连字符开头），大小写不区分。
    配置位于 Windows 用户主目录的 .pw2401/chrome.{Profile}/launch.json，浏览器数据位于 user-data/。
    例如 work 实例使用 .pw2401/chrome.work/。
    Chrome 开关使用 --名称=值 或 --名称；同名开关覆盖，其他参数保留，网址和文件路径也保存并去重。
    带空格的参数应整体引用。JSON 中的字符串不展开变量、不执行代码。
    无参数运行时先显示简短用法，再按名称列出所有已保存的 profile，逐个打印与 -Try 相同的环境覆盖和完整命令。
    没有 profile 时显示提示；单个 profile 的配置或程序路径有误时报告原因并继续显示其他 profile。

    启动器选项（大小写不敏感，除 -Help、-Try 外均保存配置并启动）：
      -ClearArgs                  清空保存的 Chrome 参数和网址，再应用本次参数。
      -SetEnv NAME=value          设置并保存子进程环境变量，可重复使用。
      -RemoveEnv NAME             删除保存的覆盖项，恢复继承，可重复使用。
      -ClearEnv                   清空环境变量覆盖项。
      -ExecutablePath PATH        保存 Chrome 可执行文件的绝对路径。
      -ResetExecutable            清除自定义路径，恢复自动查找。
      -Try                        先应用本次参数，再打印自定义环境变量设置和完整启动命令，不保存、不建目录、不启动。
      -Help                       显示完整说明和示例。

    组合选项按清空或重置、删除指定项、应用本次设置的顺序处理。
    -Try 可以放在实例名之后的任意位置；先读取保存的配置，再应用本次全部选项和 Chrome 参数后显示。
    同名开关和环境变量以本次值优先；所有变更仅在内存中生效，新实例按空配置预览。
    输出先列出自定义环境变量的 PowerShell 赋值语句，再列出程序绝对路径和全部启动参数。
    未覆盖的继承环境变量不展开打印；输出中的语句仅用于查看，不会执行。
    显式路径优先，否则依次检查 PATH、Windows App Paths 和常见安装位置。
    同一实例已运行时 Chrome 可能复用旧进程；修改启动参数或环境变量后须完全关闭该实例再启动。

.EXAMPLE
    .\chrome-profile.ps1
    显示简短用法及所有已保存 profile 的调试预览，不修改配置或启动浏览器。

.EXAMPLE
    .\chrome-profile.ps1 work --proxy-server=http://127.0.0.1:7890 https://example.com
    保存代理和网址并启动 work，以后直接运行 .\chrome-profile.ps1 work 即可复用。

.EXAMPLE
    .\chrome-profile.ps1 work -ClearArgs --incognito
    替换保存的启动参数；保留环境变量和浏览器数据。

.EXAMPLE
    .\chrome-profile.ps1 work -SetEnv 'NAME=value=with spaces' -RemoveEnv OLD_NAME
    设置环境变量并取消 OLD_NAME 的覆盖，仅作用于该 Chrome 及其子进程。

.EXAMPLE
    .\chrome-profile.ps1 work -ExecutablePath 'D:\Apps\Chrome\chrome.exe'
    保存并使用指定程序；使用 -ResetExecutable 恢复自动查找。

.EXAMPLE
    .\chrome-profile.ps1 work -Try -ClearArgs --proxy-server=http://127.0.0.1:8080
    打印替换参数后的完整启动命令，不修改配置或启动浏览器。

.EXAMPLE
    .\chrome-profile.ps1 work -Try -SetEnv 'NAME=debug' --proxy-server=http://127.0.0.1:8080
    先打印合并后的自定义环境变量设置语句，再打印包含代理参数的完整 Chrome 启动命令。

.NOTES
    Windows、PowerShell 7。可复制本文件独立使用，不依赖 pw2401.ps1 或 lib 模块。
    使用 .NET ArgumentList 保留参数边界；调试输出使用 PowerShell 引用规则，自定义环境变量设置列在启动命令之前。
#>
param()

function Assert-ChromeEnvironmentName {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name) -or $Name.Contains('=') -or $Name.Contains([char]0)) {
        throw '环境变量名称不能为空，也不能包含 = 或 NUL。'
    }
}

function Get-ChromeArgumentKey {
    param([AllowEmptyString()][string]$Argument)
    if ($Argument.Contains([char]0)) { throw 'Chrome 参数不能包含 NUL。' }
    # Chromium 在识别开关前会去掉 argv 两端空白；分类须一致，保存仍保留原字符串。
    $classifiedArgument = $Argument.Trim()
    # Chromium 在 Windows 上也接受单连字符和斜杠形式，均不能绕过目录隔离。
    if ($classifiedArgument -match '^(?:--?|/)user-data-dir(?:=|$)') {
        throw '不能覆盖 --user-data-dir；请使用不同实例名选择浏览器数据目录。'
    }
    if ($classifiedArgument.StartsWith('--', [StringComparison]::Ordinal)) {
        $name = ($classifiedArgument.Substring(2) -split '=', 2)[0]
        if ([string]::IsNullOrEmpty($name) -or $name -match '\s') {
            throw 'Chrome 开关应使用 --名称=值 或 --名称，不能使用单独的 --。'
        }
        return $name
    }
    if ($classifiedArgument.StartsWith('-', [StringComparison]::Ordinal)) {
        throw "未知启动器选项或无效 Chrome 开关：$Argument；Chrome 开关请使用 --名称=值 或 --名称。"
    }
    return $null
}

function Read-ChromeLauncherOptions {
    param([string[]]$Tokens = @())
    $options = [pscustomobject]@{
        Help = $false
        Instance = $null
        ClearArgs = $false
        ClearEnv = $false
        ResetExecutable = $false
        Try = $false
        ExecutablePath = $null
        Arguments = [Collections.Generic.List[string]]::new()
        SetEnvironment = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
        RemoveEnvironment = [Collections.Generic.List[string]]::new()
    }
    if ($Tokens.Count -eq 0 -or $Tokens[0] -ieq '-Help') {
        $options.Help = $true
        return $options
    }
    $instance = $Tokens[0]
    if ($instance -notmatch '^[a-zA-Z0-9_][a-zA-Z0-9_-]*$' -or
        $instance -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
        throw '实例名只能使用字母、数字、下划线和连字符，不能以连字符开头或使用 Windows 保留名称。'
    }
    $options.Instance = $instance.ToLowerInvariant()
    for ($index = 1; $index -lt $Tokens.Count; $index++) {
        $token = $Tokens[$index]
        switch ($token) {
            '-Help' { $options.Help = $true }
            '-ClearArgs' { $options.ClearArgs = $true }
            '-ClearEnv' { $options.ClearEnv = $true }
            '-ResetExecutable' { $options.ResetExecutable = $true }
            '-Try' { $options.Try = $true }
            { $_ -in @('-SetEnv', '-RemoveEnv', '-ExecutablePath') } {
                if ($index + 1 -ge $Tokens.Count) { throw "$token 缺少值。" }
                $index++
                $value = $Tokens[$index]
                if ($value -in @('-Help', '-ClearArgs', '-ClearEnv', '-ResetExecutable', '-Try', '-SetEnv', '-RemoveEnv', '-ExecutablePath')) {
                    throw "$token 缺少值，不能将启动器选项 $value 用作它的值。"
                }
                switch ($token) {
                    '-SetEnv' {
                        $separator = $value.IndexOf('=')
                        if ($separator -lt 1) { throw '-SetEnv 的格式应为 NAME=value。' }
                        $name = $value.Substring(0, $separator)
                        $environmentValue = $value.Substring($separator + 1)
                        Assert-ChromeEnvironmentName -Name $name
                        if ($environmentValue.Contains([char]0)) { throw '环境变量值不能包含 NUL。' }
                        $options.SetEnvironment[$name] = $environmentValue
                    }
                    '-RemoveEnv' {
                        Assert-ChromeEnvironmentName -Name $value
                        $options.RemoveEnvironment.Add($value)
                    }
                    '-ExecutablePath' {
                        if ([string]::IsNullOrWhiteSpace($value)) { throw '-ExecutablePath 不能为空。' }
                        $options.ExecutablePath = $value
                    }
                }
            }
            default {
                [void](Get-ChromeArgumentKey -Argument $token)
                $options.Arguments.Add($token)
            }
        }
    }
    return $options
}

function Merge-ChromeArguments {
    param([string[]]$ExistingArguments = @(), [string[]]$AdditionalArguments = @())
    $merged = [Collections.Generic.List[string]]::new()
    $switchPositions = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::OrdinalIgnoreCase)
    $targets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($argument in @($ExistingArguments) + @($AdditionalArguments)) {
        $key = Get-ChromeArgumentKey -Argument $argument
        if ($null -ne $key) {
            if ($switchPositions.ContainsKey($key)) { $merged[$switchPositions[$key]] = $argument }
            else {
                $switchPositions[$key] = $merged.Count
                $merged.Add($argument)
            }
        }
        elseif ($targets.Add($argument)) { $merged.Add($argument) }
    }
    return $merged.ToArray()
}

function Read-ChromeLaunchConfig {
    param([string]$Path)
    $config = [ordered]@{
        executablePath = $null
        arguments = [string[]]@()
        environment = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $config }
    try {
        $parsed = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -AsHashtable -NoEnumerate -ErrorAction Stop
        if ($parsed -isnot [Collections.IDictionary]) { throw '顶层必须是 JSON 对象。' }
        foreach ($entry in $parsed.GetEnumerator()) {
            if ($entry.Key -cnotin @('executablePath', 'arguments', 'environment')) { throw "未知配置项：$($entry.Key)" }
        }
        if ($parsed.Contains('executablePath') -and $null -ne $parsed.executablePath) {
            if ($parsed.executablePath -isnot [string] -or [string]::IsNullOrWhiteSpace($parsed.executablePath) -or
                -not [IO.Path]::IsPathFullyQualified($parsed.executablePath)) {
                throw 'executablePath 必须是绝对路径字符串或 null。'
            }
            $config.executablePath = $parsed.executablePath
        }
        if ($parsed.Contains('arguments')) {
            if ($parsed.arguments -isnot [array]) { throw 'arguments 必须是字符串数组。' }
            foreach ($argument in $parsed.arguments) {
                if ($argument -isnot [string]) { throw 'arguments 的每一项必须是非 null 字符串。' }
                [void](Get-ChromeArgumentKey -Argument $argument)
            }
            $config.arguments = [string[]]$parsed.arguments
        }
        if ($parsed.Contains('environment')) {
            if ($parsed.environment -isnot [Collections.IDictionary]) { throw 'environment 必须是 JSON 对象。' }
            foreach ($entry in $parsed.environment.GetEnumerator()) {
                Assert-ChromeEnvironmentName -Name $entry.Key
                $value = $entry.Value
                if ($value -isnot [string] -or $value.Contains([char]0)) { throw 'environment 的值必须是无 NUL 的字符串。' }
                $config.environment[$entry.Key] = $value
            }
        }
    }
    catch { throw "无法读取 Chrome 配置 '$Path'：$($_.Exception.Message)" }
    return $config
}

function Get-ChromeExecutableCandidates {
    Get-Command chrome.exe -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object { $_.Source }
    foreach ($registryPath in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'
    )) {
        try {
            $registryKey = Get-Item -LiteralPath $registryPath -ErrorAction Stop
            try { $candidate = $registryKey.GetValue('') }
            finally { $registryKey.Dispose() }
            if ($candidate -is [string] -and -not [string]::IsNullOrWhiteSpace($candidate)) {
                $candidate.Trim('"')
            }
        }
        catch { continue }
    }
    foreach ($basePath in @([Environment]::GetFolderPath('LocalApplicationData'), $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [string]::IsNullOrWhiteSpace($basePath)) { Join-Path $basePath 'Google/Chrome/Application/chrome.exe' }
    }
}

function Resolve-ChromeExecutable {
    param([string]$ExecutablePath)
    if (-not [string]::IsNullOrEmpty($ExecutablePath)) {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ExecutablePath)
        if ([IO.Path]::GetExtension($resolvedPath) -ine '.exe' -or -not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw "Chrome 可执行文件不存在或不是 .exe：$resolvedPath"
        }
        return $resolvedPath
    }
    $checkedPaths = [Collections.Generic.List[string]]::new()
    foreach ($candidate in Get-ChromeExecutableCandidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $checkedPaths.Add($candidate)
        if ([IO.Path]::IsPathFullyQualified($candidate) -and [IO.Path]::GetExtension($candidate) -ieq '.exe' -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)) { return [IO.Path]::GetFullPath($candidate) }
    }
    throw "未找到 Chrome。请使用 -ExecutablePath 指定程序。已检查：$($checkedPaths -join '; ')"
}

function ConvertTo-ChromeCommandLiteral {
    param([AllowEmptyString()][string]$Value)
    $escaped = $Value.Replace("'", "''")
    # PowerShell 也把这些排版单引号识别为引号，必须同样转义。
    foreach ($codePoint in @(0x2018, 0x2019, 0x201A, 0x201B)) {
        $quote = ([char]$codePoint).ToString()
        $escaped = $escaped.Replace($quote, $quote + $quote)
    }
    return "'" + $escaped + "'"
}

function Get-ChromeLaunchPlan {
    param(
        [string[]]$Tokens = @(),
        [string]$UserProfilePath = [Environment]::GetFolderPath('UserProfile')
    )
    if (-not $IsWindows) { throw '此 Chrome 启动器仅支持 Windows。' }
    $options = Read-ChromeLauncherOptions -Tokens $Tokens
    if ($options.Help) { throw '请使用 Invoke-ChromeLauncher 显示帮助。' }
    if ([string]::IsNullOrWhiteSpace($UserProfilePath)) { throw '无法确定 Windows 用户主目录。' }
    $instancePath = Join-Path ([IO.Path]::GetFullPath($UserProfilePath)) ".pw2401/chrome.$($options.Instance)"
    $configPath = Join-Path $instancePath 'launch.json'
    $userDataPath = Join-Path $instancePath 'user-data'
    $config = Read-ChromeLaunchConfig -Path $configPath
    if ($options.ClearArgs) { $config.arguments = [string[]]@() }
    if ($options.ClearEnv) { $config.environment.Clear() }
    if ($options.ResetExecutable) { $config.executablePath = $null }
    foreach ($name in $options.RemoveEnvironment) { [void]$config.environment.Remove($name) }
    foreach ($entry in $options.SetEnvironment.GetEnumerator()) { $config.environment[$entry.Key] = $entry.Value }
    $config.arguments = [string[]]@(Merge-ChromeArguments -ExistingArguments $config.arguments -AdditionalArguments $options.Arguments.ToArray())
    if ($null -ne $options.ExecutablePath) {
        $config.executablePath = Resolve-ChromeExecutable -ExecutablePath $options.ExecutablePath
    }
    $executable = Resolve-ChromeExecutable -ExecutablePath $config.executablePath
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $executable
    $startInfo.UseShellExecute = $false
    $startInfo.WorkingDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('.')
    $startInfo.ArgumentList.Add("--user-data-dir=$userDataPath")
    foreach ($argument in $config.arguments) { $startInfo.ArgumentList.Add($argument) }
    foreach ($entry in $config.environment.GetEnumerator()) { $startInfo.Environment[$entry.Key] = $entry.Value }
    $commandParts = @((ConvertTo-ChromeCommandLiteral -Value $executable))
    $commandParts += @(foreach ($argument in $startInfo.ArgumentList) { ConvertTo-ChromeCommandLiteral -Value $argument })
    return [pscustomobject]@{
        Instance = $options.Instance
        InstancePath = $instancePath
        ConfigPath = $configPath
        UserDataPath = $userDataPath
        Config = $config
        StartInfo = $startInfo
        Try = $options.Try
        CommandLine = '& ' + ($commandParts -join ' ')
    }
}

function Save-ChromeLaunchConfig {
    param([string]$Path, [Collections.IDictionary]$Config)
    $directory = [IO.Path]::GetDirectoryName($Path)
    [void][IO.Directory]::CreateDirectory($directory)
    $temporaryPath = Join-Path $directory ('.launch-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $json = ConvertTo-Json -InputObject $Config -Depth 5
        [IO.File]::WriteAllText($temporaryPath, $json.Replace("`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporaryPath, $Path, $true)
    }
    catch { throw "无法保存 Chrome 配置 '$Path'：$($_.Exception.Message)" }
    finally {
        if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
    }
}

function Start-ChromeProcess {
    param([Diagnostics.ProcessStartInfo]$StartInfo)
    $process = [Diagnostics.Process]::Start($StartInfo)
    if ($null -eq $process) { throw '系统未返回 Chrome 进程。' }
    $process.Dispose()
}

function ConvertTo-ChromeEnvironmentCommand {
    param([string]$Name, [AllowEmptyString()][string]$Value)
    $valueLiteral = ConvertTo-ChromeCommandLiteral -Value $Value
    if ($Name -cmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        return '$env:' + $Name + ' = ' + $valueLiteral
    }
    # 非标识符名称也允许用于进程环境，使用方法调用避免插入变量名导致语法歧义。
    $nameLiteral = ConvertTo-ChromeCommandLiteral -Value $Name
    return "[Environment]::SetEnvironmentVariable($nameLiteral, $valueLiteral, 'Process')"
}

function Show-ChromeLaunchPlan {
    param($Plan)
    Write-Output '调试预览：已应用本次参数，不保存配置、不启动浏览器。'
    Write-Output "实例：$($Plan.Instance)"
    Write-Output "配置文件：$($Plan.ConfigPath)"
    Write-Output "用户数据目录：$($Plan.UserDataPath)"
    Write-Output "程序：$($Plan.StartInfo.FileName)"
    Write-Output '自定义环境变量覆盖（Chrome 子进程）：'
    $overrides = @($Plan.Config.environment.GetEnumerator() | Sort-Object Key)
    if ($overrides.Count -eq 0) { Write-Output '（无自定义覆盖，继承当前进程环境。）' }
    foreach ($entry in $overrides) {
        Write-Output (ConvertTo-ChromeEnvironmentCommand -Name $entry.Key -Value $entry.Value)
    }
    Write-Output '启动命令：'
    Write-Output $Plan.CommandLine
}

function Show-ChromeUsage {
    Write-Output '用法：chrome-profile.ps1 <实例名> [启动器选项] [Chrome 参数或网址]'
    Write-Output '  chrome-profile.ps1 work                 启动或创建实例'
    Write-Output '  chrome-profile.ps1 work -Try [其他参数]  预览环境变量和完整命令'
    Write-Output '  chrome-profile.ps1 -Help                完整说明和示例'
    Write-Output ''
}

function Show-ChromeProfiles {
    param([string]$UserProfilePath = [Environment]::GetFolderPath('UserProfile'))
    if (-not $IsWindows) { throw '此 Chrome 启动器仅支持 Windows。' }
    if ([string]::IsNullOrWhiteSpace($UserProfilePath)) { throw '无法确定 Windows 用户主目录。' }
    $profilesPath = Join-Path ([IO.Path]::GetFullPath($UserProfilePath)) '.pw2401'
    $profilePrefix = 'chrome.'
    Write-Output "Profile 目录：$(Join-Path $profilesPath 'chrome.{Profile}')"
    $profiles = @()
    if (Test-Path -LiteralPath $profilesPath -ErrorAction Stop) {
        $profiles = @(Get-ChildItem -LiteralPath $profilesPath -Directory -Force -ErrorAction Stop |
            Where-Object { $_.Name.StartsWith($profilePrefix, [StringComparison]::OrdinalIgnoreCase) } |
            Sort-Object Name)
    }
    if ($profiles.Count -eq 0) {
        Write-Output '暂无已保存的 profile。'
        return
    }
    Write-Output "已保存的 profile（$($profiles.Count)）："
    foreach ($profile in $profiles) {
        $instance = $profile.Name.Substring($profilePrefix.Length)
        Write-Output ''
        Write-Output "Profile：$instance"
        try {
            $plan = Get-ChromeLaunchPlan -Tokens @($instance, '-Try') -UserProfilePath $UserProfilePath
            Show-ChromeLaunchPlan -Plan $plan
        }
        catch {
            Write-Output "预览失败：$($_.Exception.Message)"
        }
    }
}

function Invoke-ChromeLauncher {
    param(
        [string[]]$Tokens = @(),
        [string]$UserProfilePath = [Environment]::GetFolderPath('UserProfile')
    )
    $options = Read-ChromeLauncherOptions -Tokens $Tokens
    if ($options.Help) {
        if ($Tokens.Count -eq 0) {
            Show-ChromeUsage
            Show-ChromeProfiles -UserProfilePath $UserProfilePath
        }
        else {
            Get-Help -Name $PSCommandPath -Full | Out-String -Width 120 | Write-Output
        }
        return
    }
    $plan = Get-ChromeLaunchPlan -Tokens $Tokens -UserProfilePath $UserProfilePath
    if ($plan.Try) {
        Show-ChromeLaunchPlan -Plan $plan
        return
    }
    Save-ChromeLaunchConfig -Path $plan.ConfigPath -Config $plan.Config
    try {
        [void][IO.Directory]::CreateDirectory($plan.UserDataPath)
        Start-ChromeProcess -StartInfo $plan.StartInfo
    }
    catch { throw "启动 Chrome 失败，配置已保存至 '$($plan.ConfigPath)'：$($_.Exception.Message)" }
    Write-Output "已发送 Chrome 启动请求：$($plan.Instance)"
    Write-Output "配置：$($plan.ConfigPath)"
    Write-Output '若该实例已运行，新参数和环境变量需要完全关闭该实例后再启动才能可靠生效。'
}

# 点源只加载函数，便于在隔离目录中替换进程启动函数执行回归测试。
if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-ChromeLauncher -Tokens $args }
    catch {
        Write-Error -Message $_.Exception.Message -ErrorAction Continue
        exit 1
    }
}

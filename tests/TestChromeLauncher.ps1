# Focused standalone Chrome launcher regressions; never launches a real browser.
param(
    [string]$WorkDir = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runRoot = Join-Path ([IO.Path]::GetFullPath($WorkDir)) ('target/pw2401-tests/chrome/' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($runRoot)
$results = [Collections.Generic.List[object]]::new()
$script:testExecutable = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
$script:startedProcesses = [Collections.Generic.List[Diagnostics.ProcessStartInfo]]::new()
$script:caseProfilePath = ''

. (Join-Path $projectRoot 'standalone/chrome-profile.ps1')

# Mock both discovery and launch at the script boundary: tests require neither an
# installed Chrome nor access to the current user's .pw2401 directory.
function Get-ChromeExecutableCandidates {
    $script:testExecutable
}

function Start-ChromeProcess {
    param([Diagnostics.ProcessStartInfo]$StartInfo)
    $script:startedProcesses.Add($StartInfo)
}

function Assert-ChromeTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-ChromeFailure {
    param([scriptblock]$Body)
    $failed = $false
    try { & $Body | Out-Null }
    catch { $failed = $true }
    Assert-ChromeTest $failed 'Expected the launcher to reject this input.'
}

function Assert-ChromeSequence {
    param([object[]]$Actual, [object[]]$Expected, [string]$Message)
    Assert-ChromeTest ($Actual.Count -eq $Expected.Count) "$Message (item count)"
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        Assert-ChromeTest ([string]$Actual[$index] -ceq [string]$Expected[$index]) "$Message (item $index)"
    }
}

function Get-ChromeTestPlan {
    param([string[]]$Tokens)
    Get-ChromeLaunchPlan -Tokens $Tokens -UserProfilePath $script:caseProfilePath
}

function Invoke-ChromeTestLaunch {
    param([string[]]$Tokens)
    Invoke-ChromeLauncher -Tokens $Tokens -UserProfilePath $script:caseProfilePath
}

function Get-ChromeTestDisplayedEnvironment {
    param([string]$Output, [string]$CommandLine)
    $environmentHeader = '自定义环境变量覆盖（Chrome 子进程）：'
    $environmentStart = $Output.IndexOf($environmentHeader)
    $commandStart = $Output.LastIndexOf('启动命令：')
    Assert-ChromeTest ($environmentStart -ge 0 -and $commandStart -gt $environmentStart) 'Preview must display custom environment commands before the launch command.'
    Assert-ChromeTest ($Output.IndexOf($CommandLine, $commandStart) -gt $commandStart) 'Preview omitted the launch command after the environment commands.'
    $environmentStart += $environmentHeader.Length
    $source = $Output.Substring($environmentStart, $commandStart - $environmentStart).Trim()
    $environment = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    $names = [Collections.Generic.List[string]]::new()
    if ($source -eq '（无自定义覆盖，继承当前进程环境。）') {
        return [pscustomobject]@{ Environment = $environment; Names = [string[]]@(); Source = '' }
    }
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
    Assert-ChromeTest ($errors.Count -eq 0) 'Displayed environment commands are not valid PowerShell syntax.'
    foreach ($statement in $ast.EndBlock.Statements) {
        if ($statement -is [Management.Automation.Language.AssignmentStatementAst]) {
            Assert-ChromeTest ($statement.Left -is [Management.Automation.Language.VariableExpressionAst] -and $statement.Left.VariablePath.UserPath.StartsWith('env:', [StringComparison]::OrdinalIgnoreCase)) 'Preview assigned a non-environment variable.'
            Assert-ChromeTest ($statement.Operator -eq [Management.Automation.Language.TokenKind]::Equals) 'Preview used a non-replacement environment assignment.'
            Assert-ChromeTest ($statement.Right -is [Management.Automation.Language.CommandExpressionAst] -and $statement.Right.Expression -is [Management.Automation.Language.StringConstantExpressionAst]) 'Environment value contains executable expressions.'
            $name = $statement.Left.VariablePath.UserPath.Substring(4)
            $value = $statement.Right.Expression.SafeGetValue()
        }
        else {
            Assert-ChromeTest ($statement -is [Management.Automation.Language.PipelineAst] -and $statement.PipelineElements.Count -eq 1 -and $statement.PipelineElements[0] -is [Management.Automation.Language.CommandExpressionAst]) 'Preview contains an unexpected environment command.'
            $call = $statement.PipelineElements[0].Expression
            Assert-ChromeTest ($call -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $call.Static -and $call.Expression -is [Management.Automation.Language.TypeExpressionAst] -and $call.Expression.TypeName.FullName -eq 'Environment' -and $call.Member.Value -eq 'SetEnvironmentVariable' -and $call.Arguments.Count -eq 3) 'Unusual environment name did not use the safe process-environment setter.'
            foreach ($argument in $call.Arguments) {
                Assert-ChromeTest ($argument -is [Management.Automation.Language.StringConstantExpressionAst]) 'Environment setter contains executable arguments.'
            }
            $name = $call.Arguments[0].SafeGetValue()
            $value = $call.Arguments[1].SafeGetValue()
            Assert-ChromeTest ($call.Arguments[2].SafeGetValue() -ceq 'Process') 'Preview targets persistent user or system environment settings.'
        }
        Assert-ChromeTest (-not $environment.ContainsKey($name)) 'Preview repeats an environment override.'
        $environment[$name] = $value
        $names.Add($name)
    }
    return [pscustomobject]@{ Environment = $environment; Names = $names.ToArray(); Source = $source }
}

function Get-ChromeTestConfigPath {
    param([string]$Instance = 'work')
    Join-Path $script:caseProfilePath ".pw2401/chrome.$Instance/launch.json"
}

function Write-ChromeTestConfig {
    param([string]$Json, [string]$Instance = 'work')
    $path = Get-ChromeTestConfigPath $Instance
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path, $Json, [Text.UTF8Encoding]::new($false))
}

function Get-ChromeTestTreeSnapshot {
    param([string]$Path)
    $entries = @(Get-ChildItem -LiteralPath $Path -Recurse -Force | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{
            Path = $_.FullName
            Directory = $_.PSIsContainer
            # Directory enumeration can expose stale timestamps after fixture creation on Windows.
            LastWriteTicks = if ($_.PSIsContainer) { $null } else { $_.LastWriteTimeUtc.Ticks }
            Content = if ($_.PSIsContainer) { $null } else { [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName)) }
        }
    })
    ConvertTo-Json -InputObject $entries -Depth 3 -Compress
}

function Invoke-ChromeTestCase {
    param([string]$Name, [scriptblock]$Body)
    $script:caseProfilePath = Join-Path $runRoot "$Name/profile"
    $script:startedProcesses.Clear()
    try {
        & $Body
        $results.Add([pscustomobject]@{ Name = $Name; Status = 'Pass'; Message = '' })
    }
    catch {
        $results.Add([pscustomobject]@{ Name = $Name; Status = 'Fail'; Message = ($_ | Out-String).Trim() })
    }
}

Invoke-ChromeTestCase 'help-without-side-effects' {
    foreach ($tokens in @(@(), @('-Help'))) {
        $output = Invoke-ChromeTestLaunch -Tokens $tokens *>&1 | Out-String
        Assert-ChromeTest ($output.Contains('-Try')) 'Help omitted the preview option.'
    }
    $entryOutput = & $script:testExecutable -NoProfile -File (Join-Path $projectRoot 'standalone/chrome-profile.ps1') -Help 2>&1 | Out-String
    Assert-ChromeTest ($LASTEXITCODE -eq 0 -and $entryOutput.Contains('-Try')) 'The standalone entry point did not display help successfully.'
    Assert-ChromeTest ($entryOutput.Contains('-ResetExecutable') -and $entryOutput.Contains('NAME=value=with spaces')) 'Explicit Help omitted detailed options or examples.'
    Assert-ChromeTest (-not [IO.Directory]::Exists($script:caseProfilePath)) 'Help created a profile directory.'
    Assert-ChromeTest ($script:startedProcesses.Count -eq 0) 'Help started a process.'
}

Invoke-ChromeTestCase 'no-arguments-missing-or-empty-profile-root' {
    $output = Invoke-ChromeTestLaunch -Tokens @() *>&1 | Out-String
    Assert-ChromeTest ($output.Contains('用法：chrome-profile.ps1') -and $output.Contains('-Try') -and $output.Contains('-Help')) 'No-argument invocation omitted brief usage or the full-help entry point.'
    Assert-ChromeTest (-not $output.Contains('-ResetExecutable') -and -not $output.Contains('NAME=value=with spaces')) 'No-argument invocation expanded the detailed help or examples.'
    Assert-ChromeTest ($output.Contains('暂无已保存的 profile')) 'Missing profile root did not produce an empty-list message.'
    $directoryTemplate = Join-Path $script:caseProfilePath '.pw2401/chrome.{Profile}'
    Assert-ChromeTest ($output.Contains($directoryTemplate)) 'Profile overview omitted the chrome.{Profile} directory template.'
    Assert-ChromeTest (-not [IO.Directory]::Exists($script:caseProfilePath)) 'Listing a missing profile root created directories.'
    $root = Join-Path $script:caseProfilePath '.pw2401'
    [void][IO.Directory]::CreateDirectory($root)
    $before = Get-ChromeTestTreeSnapshot -Path $script:caseProfilePath
    $emptyOutput = Invoke-ChromeTestLaunch -Tokens @() *>&1 | Out-String
    Assert-ChromeTest ($emptyOutput.Contains('暂无已保存的 profile')) 'Empty profile root did not produce an empty-list message.'
    Assert-ChromeTest ((Get-ChromeTestTreeSnapshot -Path $script:caseProfilePath) -ceq $before) 'Listing an empty root changed the directory tree.'
    Assert-ChromeTest ($script:startedProcesses.Count -eq 0) 'Listing an empty or missing root launched a process.'
}

Invoke-ChromeTestCase 'no-arguments-lists-sorted-profile-previews-read-only' {
    $variable = 'PW2401_CHROME_LIST_PARENT'
    $originalValue = [Environment]::GetEnvironmentVariable($variable, 'Process')
    try {
        [Environment]::SetEnvironmentVariable($variable, 'parent-value', 'Process')
        Invoke-ChromeTestLaunch -Tokens @('z-work', '--proxy-server=http://127.0.0.1:7890', '-SetEnv', "$variable=z-override", '-SetEnv', 'PW2401_CHROME_Z_ONLY=last') | Out-Null
        Invoke-ChromeTestLaunch -Tokens @('alpha', '--title=中文 空格="引号"', 'https://example.com', '-SetEnv', "$variable=alpha-override", '-SetEnv', "PW2401_CHROME_ALPHA_ONLY=it's=literal") | Out-Null
        $browserData = Join-Path $script:caseProfilePath '.pw2401/chrome.browser-only/user-data'
        [void][IO.Directory]::CreateDirectory($browserData)
        [IO.File]::WriteAllText((Join-Path $browserData 'browser-data.marker'), 'keep-browser-data')
        [IO.File]::WriteAllText((Join-Path $script:caseProfilePath '.pw2401/chrome.ignore-this-file'), 'not-a-profile')
        foreach ($unrelatedDirectory in @('edge.work', 'chromework', 'chrome/legacy-work')) {
            $unrelatedPath = Join-Path (Join-Path $script:caseProfilePath '.pw2401') $unrelatedDirectory
            [void][IO.Directory]::CreateDirectory($unrelatedPath)
            [IO.File]::WriteAllText((Join-Path $unrelatedPath 'launch.json'), '{broken-json')
        }
        $script:startedProcesses.Clear()
        $before = Get-ChromeTestTreeSnapshot -Path $script:caseProfilePath
        $output = Invoke-ChromeTestLaunch -Tokens @() *>&1 | Out-String
        $previousIndex = $output.IndexOf('-Try')
        Assert-ChromeTest ($previousIndex -ge 0) 'No-argument invocation omitted brief usage before profile previews.'
        foreach ($instance in @('alpha', 'browser-only', 'z-work')) {
            $preview = Invoke-ChromeTestLaunch -Tokens @($instance, '-Try') *>&1 | Out-String
            Assert-ChromeTest ($output.Contains($preview.Trim())) "Profile '$instance' differs from its individual Try preview."
            $index = $output.IndexOf("实例：$instance")
            Assert-ChromeTest ($index -gt $previousIndex) 'Profile previews are not sorted after the help output.'
            $previousIndex = $index
        }
        foreach ($ignored in @('ignore-this-file', 'edge.work', 'chromework', 'legacy-work')) {
            Assert-ChromeTest (-not $output.Contains($ignored)) "Unrelated entry '$ignored' was listed as a Chrome profile."
        }
        Assert-ChromeTest ([regex]::Matches($output, '实例：').Count -eq 3 -and -not $output.Contains('预览失败：')) 'Profile overview included an unrelated directory or file.'
        Assert-ChromeTest ($output.Contains('$env:PW2401_CHROME_ALPHA_ONLY = ') -and $output.Contains('$env:PW2401_CHROME_Z_ONLY = ')) 'Profile listing omitted a saved custom environment override.'
        Assert-ChromeTest ((Get-ChromeTestTreeSnapshot -Path $script:caseProfilePath) -ceq $before) 'Profile listing changed configuration or browser data.'
        Assert-ChromeTest (-not [IO.File]::Exists((Get-ChromeTestConfigPath 'browser-only'))) 'Listing a browser-data-only profile created configuration.'
        Assert-ChromeTest ([Environment]::GetEnvironmentVariable($variable, 'Process') -ceq 'parent-value') 'Profile listing applied an override to the parent environment.'
        Assert-ChromeTest ($script:startedProcesses.Count -eq 0) 'Profile listing launched a process.'
        $help = Invoke-ChromeTestLaunch -Tokens @('-Help') *>&1 | Out-String
        Assert-ChromeTest (-not $help.Contains('实例：alpha') -and -not $help.Contains('$env:PW2401_CHROME_ALPHA_ONLY = ')) 'Explicit Help unexpectedly listed saved profiles.'
    }
    finally { [Environment]::SetEnvironmentVariable($variable, $originalValue, 'Process') }
}

Invoke-ChromeTestCase 'no-arguments-continues-after-invalid-profiles' {
    Write-ChromeTestConfig -Instance 'a-broken' -Json '{broken-json'
    $invalidExecutable = Join-Path $script:caseProfilePath 'missing-chrome.exe'
    $invalidConfig = @{ executablePath = $invalidExecutable; arguments = @(); environment = @{} } | ConvertTo-Json
    Write-ChromeTestConfig -Instance 'b-missing-exe' -Json $invalidConfig
    [void][IO.Directory]::CreateDirectory((Join-Path $script:caseProfilePath '.pw2401/chrome.invalid name'))
    Invoke-ChromeTestLaunch -Tokens @('z-valid', '--incognito', '-SetEnv', 'PW2401_CHROME_VALID=yes') | Out-Null
    $script:startedProcesses.Clear()
    $before = Get-ChromeTestTreeSnapshot -Path $script:caseProfilePath
    $output = Invoke-ChromeTestLaunch -Tokens @() *>&1 | Out-String
    foreach ($name in @('a-broken', 'b-missing-exe', 'invalid name')) {
        Assert-ChromeTest ($output.Contains($name)) "Profile listing omitted invalid profile '$name' instead of reporting its error."
    }
    Assert-ChromeTest ([regex]::Matches($output, '预览失败：').Count -eq 3) 'Profile listing did not report each invalid profile separately.'
    $validPreview = Invoke-ChromeTestLaunch -Tokens @('z-valid', '-Try') *>&1 | Out-String
    Assert-ChromeTest ($output.Contains($validPreview.Trim())) 'Invalid profile prevented a later valid profile preview.'
    Assert-ChromeTest ($output.Contains($invalidExecutable)) 'Invalid executable diagnostic omitted the failing path.'
    Assert-ChromeTest ((Get-ChromeTestTreeSnapshot -Path $script:caseProfilePath) -ceq $before) 'Listing invalid profiles altered saved files or directories.'
    Assert-ChromeTest ($script:startedProcesses.Count -eq 0) 'Listing invalid profiles launched a process.'
}

Invoke-ChromeTestCase 'initial-plan-and-instance-isolation' {
    $work = Get-ChromeTestPlan -Tokens @('WORK')
    $other = Get-ChromeTestPlan -Tokens @('personal')
    Assert-ChromeTest ($work.Instance -ceq 'work') 'Instance names were not normalized.'
    Assert-ChromeTest ($work.ConfigPath -eq (Get-ChromeTestConfigPath)) 'Configuration path is incorrect.'
    Assert-ChromeTest ($work.UserDataPath -eq (Join-Path $script:caseProfilePath '.pw2401/chrome.work/user-data')) 'Chrome data path is incorrect.'
    Assert-ChromeTest ($work.UserDataPath -ne $other.UserDataPath) 'Two instances share Chrome data.'
    Assert-ChromeTest ($work.StartInfo.FileName -eq $script:testExecutable) 'Executable discovery was not used.'
    Assert-ChromeSequence @($work.StartInfo.ArgumentList) @("--user-data-dir=$($work.UserDataPath)") 'Initial launch arguments are incorrect.'
    Assert-ChromeTest (-not $work.StartInfo.UseShellExecute) 'Process would bypass explicit environment/argument handling.'
    Assert-ChromeTest (-not [IO.Directory]::Exists($script:caseProfilePath)) 'Building a plan created files.'
}

Invoke-ChromeTestCase 'save-and-reuse-configuration' {
    Invoke-ChromeTestLaunch -Tokens @('work', '-ExecutablePath', $script:testExecutable, '--proxy-server=http://127.0.0.1:7890', 'https://example.com') | Out-Null
    Assert-ChromeTest ($script:startedProcesses.Count -eq 1) 'Initial invocation did not start exactly once.'
    $path = Get-ChromeTestConfigPath
    $saved = [IO.File]::ReadAllText($path) | ConvertFrom-Json -AsHashtable
    Assert-ChromeTest ($saved.executablePath -eq $script:testExecutable) 'Explicit executable was not saved.'
    Assert-ChromeSequence @($saved.arguments) @('--proxy-server=http://127.0.0.1:7890', 'https://example.com') 'Arguments were not saved.'
    Invoke-ChromeTestLaunch -Tokens @('work') | Out-Null
    Assert-ChromeTest ($script:startedProcesses.Count -eq 2) 'Saved instance did not start.'
    Assert-ChromeSequence @($script:startedProcesses[1].ArgumentList) @($script:startedProcesses[0].ArgumentList) 'Restart did not reuse saved arguments.'
    Invoke-ChromeTestLaunch -Tokens @('personal', '--incognito') | Out-Null
    $work = Get-ChromeTestPlan -Tokens @('work')
    Assert-ChromeSequence @($work.Config.arguments) @($saved.arguments) 'Changing another instance affected work.'
    Assert-ChromeTest ([IO.File]::Exists((Get-ChromeTestConfigPath 'personal'))) 'Second instance was not saved separately.'
}

Invoke-ChromeTestCase 'merge-switches-and-targets' {
    Invoke-ChromeTestLaunch -Tokens @('work', '--proxy-server=old', '--enable-features=One,Two', 'https://example.com', '--incognito') | Out-Null
    $plan = Get-ChromeTestPlan -Tokens @('work', '--proxy-server=middle', '--proxy-server=new', '--enable-features=Three', 'https://example.com', 'https://example.org')
    Assert-ChromeSequence @($plan.Config.arguments) @('--proxy-server=new', '--enable-features=Three', 'https://example.com', '--incognito', 'https://example.org') 'Switch replacement or target deduplication changed order.'
    Assert-ChromeSequence @($plan.StartInfo.ArgumentList) (@("--user-data-dir=$($plan.UserDataPath)") + @($plan.Config.arguments)) 'Base argument was not followed by user arguments.'
}

Invoke-ChromeTestCase 'clear-arguments-keeps-browser-data-and-environment' {
    Invoke-ChromeTestLaunch -Tokens @('work', '--incognito', 'https://example.com', '-SetEnv', 'PW2401_CHROME_KEEP=original') | Out-Null
    $plan = Get-ChromeTestPlan -Tokens @('work')
    [void][IO.Directory]::CreateDirectory($plan.UserDataPath)
    $marker = Join-Path $plan.UserDataPath 'browser-data.marker'
    [IO.File]::WriteAllText($marker, 'preserve-this-browser-data')
    Invoke-ChromeTestLaunch -Tokens @('work', '-ClearArgs', '--proxy-server=replacement') | Out-Null
    $updated = Get-ChromeTestPlan -Tokens @('work')
    Assert-ChromeSequence @($updated.Config.arguments) @('--proxy-server=replacement') 'ClearArgs did not replace all saved arguments.'
    Assert-ChromeTest ($updated.Config.environment['PW2401_CHROME_KEEP'] -ceq 'original') 'ClearArgs removed environment overrides.'
    Assert-ChromeTest ([IO.File]::ReadAllText($marker) -ceq 'preserve-this-browser-data') 'ClearArgs changed browser data.'
    Invoke-ChromeTestLaunch -Tokens @('work', '-ClearArgs') | Out-Null
    Assert-ChromeTest (@((Get-ChromeTestPlan -Tokens @('work')).Config.arguments).Count -eq 0) 'ClearArgs without new switches left arguments behind.'
}

Invoke-ChromeTestCase 'environment-precedence-and-parent-isolation' {
    $variable = 'PW2401_CHROME_TEST_PARENT'
    $originalValue = [Environment]::GetEnvironmentVariable($variable, 'Process')
    try {
        [Environment]::SetEnvironmentVariable($variable, 'inherited-value', 'Process')
        Invoke-ChromeTestLaunch -Tokens @('work', '-SetEnv', "$variable=stored-value", '-SetEnv', 'PW2401_CHROME_DROP=drop') | Out-Null
        $updated = Get-ChromeTestPlan -Tokens @('work', '-SetEnv', 'pw2401_chrome_test_parent=new=value', '-RemoveEnv', $variable)
        Assert-ChromeTest ($updated.StartInfo.Environment[$variable] -ceq 'new=value') 'SetEnv was not applied after removal or was case sensitive.'
        Assert-ChromeTest (@($updated.Config.environment.Keys | Where-Object { $_ -ieq $variable }).Count -eq 1) 'Environment contains duplicate case variants.'
        $removed = Get-ChromeTestPlan -Tokens @('work', '-RemoveEnv', $variable, '-RemoveEnv', 'PW2401_CHROME_DROP')
        Assert-ChromeTest ($removed.StartInfo.Environment[$variable] -ceq 'inherited-value') 'Removing an override did not restore inheritance.'
        Assert-ChromeTest ($removed.Config.environment.Count -eq 0) 'Repeated RemoveEnv did not remove both overrides.'
        $cleared = Get-ChromeTestPlan -Tokens @('work', '-SetEnv', 'PW2401_CHROME_NEW=', '-ClearEnv', '-SetEnv', 'PW2401_CHROME_NEW=final')
        Assert-ChromeTest ($cleared.Config.environment.Count -eq 1) 'ClearEnv did not remove the saved environment.'
        Assert-ChromeTest ($cleared.Config.environment['PW2401_CHROME_NEW'] -ceq 'final') 'Last repeated SetEnv did not win.'
        $empty = Get-ChromeTestPlan -Tokens @('work', '-ClearEnv', '-SetEnv', 'PW2401_CHROME_EMPTY=')
        Assert-ChromeTest ($empty.StartInfo.Environment.ContainsKey('PW2401_CHROME_EMPTY') -and $empty.StartInfo.Environment['PW2401_CHROME_EMPTY'] -ceq '') 'Empty environment value was lost.'
        Assert-ChromeTest ([Environment]::GetEnvironmentVariable($variable, 'Process') -ceq 'inherited-value') 'Planning or launch changed the parent environment.'
    }
    finally { [Environment]::SetEnvironmentVariable($variable, $originalValue, 'Process') }
}

Invoke-ChromeTestCase 'literal-round-trip-and-command-quoting' {
    $arguments = @('--custom=中文 空格="引号"=尾', "--title=it's literal", 'D:\中文 目录\page[1].html', '--text=$env:PATH;$(not-a-command)')
    foreach ($codePoint in @(0x2018, 0x2019, 0x201A, 0x201B)) {
        $arguments += '--title-' + $codePoint + '=O' + [char]$codePoint + 'Reilly'
    }
    Invoke-ChromeTestLaunch -Tokens (@('work', '-SetEnv', 'PW2401_CHROME_LITERAL=中文 空格="引号"=尾') + $arguments) | Out-Null
    $plan = Get-ChromeTestPlan -Tokens @('work')
    Assert-ChromeSequence @($plan.Config.arguments) $arguments 'Literal arguments did not survive JSON round trip.'
    Assert-ChromeTest ($plan.StartInfo.Environment['PW2401_CHROME_LITERAL'] -ceq '中文 空格="引号"=尾') 'Environment value did not survive JSON round trip.'
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($plan.CommandLine, [ref]$tokens, [ref]$errors)
    Assert-ChromeTest ($errors.Count -eq 0) 'Rendered PowerShell command is not valid syntax.'
    $commands = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true))
    Assert-ChromeTest ($commands.Count -eq 1) 'Rendered command contains executable expansions.'
    $literals = @($commands[0].CommandElements | ForEach-Object { $_.SafeGetValue() })
    Assert-ChromeSequence $literals (@($script:testExecutable) + @($plan.StartInfo.ArgumentList)) 'Rendered command does not reproduce executable and arguments.'
}

Invoke-ChromeTestCase 'environment-dictionary-member-names' {
    Invoke-ChromeTestLaunch -Tokens @('work', '-SetEnv', 'Keys=literal-key-value', '-SetEnv', 'Count=literal-count-value', '-SetEnv', 'Values=literal-values-value') | Out-Null
    $plan = Get-ChromeTestPlan -Tokens @('work', '-Try')
    $output = Invoke-ChromeTestLaunch -Tokens @('work', '-Try') *>&1 | Out-String
    $shown = (Get-ChromeTestDisplayedEnvironment -Output $output -CommandLine $plan.CommandLine).Environment
    foreach ($pair in @(@('Keys', 'literal-key-value'), @('Count', 'literal-count-value'), @('Values', 'literal-values-value'))) {
        Assert-ChromeTest ($plan.Config.environment[$pair[0]] -ceq $pair[1]) 'A dictionary member name did not persist as an environment key.'
        Assert-ChromeTest ($plan.StartInfo.Environment[$pair[0]] -ceq $pair[1]) 'A dictionary member name was not added to the child environment.'
        Assert-ChromeTest ($shown[$pair[0]] -ceq $pair[1]) 'Try lost an environment key named after a dictionary member.'
    }
    Assert-ChromeTest (@($plan.Config.environment.GetEnumerator()).Count -eq 3) 'Saving member names introduced extra environment variables.'
}

Invoke-ChromeTestCase 'reset-executable-and-case-insensitive-controls' {
    Invoke-ChromeTestLaunch -Tokens @('work', '-eXeCuTaBlEpAtH', $script:testExecutable, '--incognito') | Out-Null
    Invoke-ChromeTestLaunch -Tokens @('work', '-rEsEtExEcUtAbLe') | Out-Null
    $plan = Get-ChromeTestPlan -Tokens @('work')
    Assert-ChromeTest ($null -eq $plan.Config.executablePath) 'ResetExecutable did not persist automatic discovery.'
    Assert-ChromeTest ($plan.StartInfo.FileName -eq $script:testExecutable) 'ResetExecutable did not rediscover the executable.'
    $combined = Get-ChromeTestPlan -Tokens @('work', '-ExecutablePath', $script:testExecutable, '-ResetExecutable', '-cLeArArGs', '-sEtEnV', 'PW2401_CHROME_CASE=yes')
    Assert-ChromeTest ($combined.Config.executablePath -eq $script:testExecutable) 'Executable override was not applied after reset.'
    Assert-ChromeTest (@($combined.Config.arguments).Count -eq 0) 'ClearArgs control was case sensitive.'
    Assert-ChromeTest ($combined.StartInfo.Environment['PW2401_CHROME_CASE'] -eq 'yes') 'SetEnv control was case sensitive.'
}

Invoke-ChromeTestCase 'try-new-instance-is-read-only-and-complete' {
    $variable = 'PW2401_CHROME_INHERITED_SENTINEL'
    $originalValue = [Environment]::GetEnvironmentVariable($variable, 'Process')
    $overrideVariable = 'PW2401_CHROME_TRY'
    $originalOverride = [Environment]::GetEnvironmentVariable($overrideVariable, 'Process')
    $longValue = 'start-' + ('x' * 8192) + '-end'
    try {
        [Environment]::SetEnvironmentVariable($variable, 'inherited-only-sentinel-value', 'Process')
        [Environment]::SetEnvironmentVariable($overrideVariable, 'parent-value', 'Process')
        $literalValue = "中文 'quoted' `"double quoted`" " + '$env:PATH;$(not-a-command)'
        foreach ($codePoint in @(0x2018, 0x2019, 0x201A, 0x201B)) { $literalValue += [char]$codePoint }
        $tokens = @('new', '-tRy', '-ClearArgs', '--proxy-server=preview', '-ClearEnv', '-RemoveEnv', 'MISSING', '-SetEnv', 'PW2401_CHROME_TRY=preview', '-SetEnv', "PW2401_CHROME_TRY_QUOTES=$literalValue", '-SetEnv', "PW2401_CHROME_TRY_LINES=first`nsecond", '-SetEnv', "PW2401_CHROME_TRY_LONG=$longValue", '-SetEnv', "PW2401-CHROME O'Reilly=unusual name's literal value", '-SetEnv', 'PW2401_CHROME_TRY_EMPTY=', '-ResetExecutable', '-ExecutablePath', $script:testExecutable)
        $plan = Get-ChromeTestPlan -Tokens $tokens
        $output = Invoke-ChromeTestLaunch -Tokens $tokens *>&1 | Out-String
        Assert-ChromeTest ($plan.Try) 'Try flag was not captured.'
        foreach ($expected in @($plan.ConfigPath, $plan.UserDataPath, $script:testExecutable, $plan.CommandLine, $longValue, 'PW2401_CHROME_TRY', 'preview')) {
            Assert-ChromeTest ($output.Contains($expected)) 'Try omitted or truncated a required value.'
        }
        $shown = Get-ChromeTestDisplayedEnvironment -Output $output -CommandLine $plan.CommandLine
        Assert-ChromeTest (@($shown.Environment.GetEnumerator()).Count -eq @($plan.Config.environment.GetEnumerator()).Count) 'Try displayed inherited variables or omitted custom overrides.'
        foreach ($pair in $plan.Config.environment.GetEnumerator()) {
            Assert-ChromeTest ($shown.Environment[$pair.Key] -ceq $pair.Value) "Try changed custom environment value: $($pair.Key)"
        }
        Assert-ChromeSequence @($shown.Names) @($shown.Names | Sort-Object) 'Try did not sort custom environment names.'
        Assert-ChromeTest (-not $output.Contains($variable) -and -not $output.Contains('inherited-only-sentinel-value')) 'Try exposed an unrelated inherited environment variable.'
        Assert-ChromeTest ($plan.StartInfo.Environment[$variable] -ceq 'inherited-only-sentinel-value') 'Hiding inherited variables removed them from the child environment.'
        Assert-ChromeTest ($shown.Source.Contains('[Environment]::SetEnvironmentVariable(')) 'Unusual environment names were not rendered with the fallback setter.'
        Assert-ChromeTest ($shown.Source.Contains('$env:PW2401_CHROME_TRY = ')) 'Ordinary environment names were not rendered as readable assignments.'
        Assert-ChromeTest ([Environment]::GetEnvironmentVariable($overrideVariable, 'Process') -ceq 'parent-value') 'Try applied an environment command to the parent process.'
        Assert-ChromeTest (-not [IO.Directory]::Exists($script:caseProfilePath)) 'Try created a previously nonexistent instance.'
        Assert-ChromeTest ($script:startedProcesses.Count -eq 0) 'Try launched a process.'
    }
    finally {
        [Environment]::SetEnvironmentVariable($variable, $originalValue, 'Process')
        [Environment]::SetEnvironmentVariable($overrideVariable, $originalOverride, 'Process')
    }
}

Invoke-ChromeTestCase 'try-without-custom-environment' {
    $plan = Get-ChromeTestPlan -Tokens @('new', '-Try')
    $output = Invoke-ChromeTestLaunch -Tokens @('new', '-Try') *>&1 | Out-String
    $shown = Get-ChromeTestDisplayedEnvironment -Output $output -CommandLine $plan.CommandLine
    Assert-ChromeTest ($shown.Names.Count -eq 0) 'Try printed inherited environment entries for an instance without overrides.'
    Assert-ChromeTest ($output.Contains('（无自定义覆盖，继承当前进程环境。）')) 'Try did not explain the absence of custom environment overrides.'
    Assert-ChromeTest (-not $output.Contains('$env:') -and -not $output.Contains('[Environment]::SetEnvironmentVariable(')) 'Try displayed environment assignments without custom overrides.'
    Assert-ChromeTest (-not [IO.Directory]::Exists($script:caseProfilePath) -and $script:startedProcesses.Count -eq 0) 'Try without custom environment caused side effects.'
}

Invoke-ChromeTestCase 'try-existing-instance-does-not-save' {
    Invoke-ChromeTestLaunch -Tokens @('work', '--incognito', '-SetEnv', 'PW2401_CHROME_SAVED=keep') | Out-Null
    $path = Get-ChromeTestConfigPath
    $before = [IO.File]::ReadAllBytes($path)
    $beforeWrite = [IO.File]::GetLastWriteTimeUtc($path)
    $script:startedProcesses.Clear()
    $tokens = @('work', '-Try', '-ClearArgs', '--proxy-server=preview', '-ClearEnv', '-RemoveEnv', 'PW2401_CHROME_SAVED', '-SetEnv', 'PW2401_CHROME_ONLY_PREVIEW=yes', '-ResetExecutable')
    $preview = Get-ChromeTestPlan -Tokens $tokens
    $output = Invoke-ChromeTestLaunch -Tokens $tokens *>&1 | Out-String
    Assert-ChromeSequence @($preview.Config.arguments) @('--proxy-server=preview') 'Preview did not calculate the edited arguments.'
    Assert-ChromeTest ($preview.Config.environment.Count -eq 1 -and $preview.Config.environment['PW2401_CHROME_ONLY_PREVIEW'] -eq 'yes') 'Preview did not calculate the edited environment.'
    Assert-ChromeTest ($output.Contains($preview.CommandLine)) 'Try output differs from the calculated command.'
    $shown = Get-ChromeTestDisplayedEnvironment -Output $output -CommandLine $preview.CommandLine
    Assert-ChromeSequence @($shown.Names) @('PW2401_CHROME_ONLY_PREVIEW') 'ClearEnv did not remove saved variables from the printed assignments.'
    Assert-ChromeTest (-not $output.Contains('PW2401_CHROME_SAVED')) 'Preview printed an environment override that was cleared.'
    $removedPlan = Get-ChromeTestPlan -Tokens @('work', '-Try', '-RemoveEnv', 'PW2401_CHROME_SAVED')
    $removedOutput = Invoke-ChromeTestLaunch -Tokens @('work', '-Try', '-RemoveEnv', 'PW2401_CHROME_SAVED') *>&1 | Out-String
    $removedShown = Get-ChromeTestDisplayedEnvironment -Output $removedOutput -CommandLine $removedPlan.CommandLine
    Assert-ChromeTest ($removedShown.Names.Count -eq 0 -and -not $removedOutput.Contains('PW2401_CHROME_SAVED')) 'RemoveEnv did not remove the saved variable from the printed assignments.'
    Assert-ChromeSequence @([IO.File]::ReadAllBytes($path)) @($before) 'Try rewrote saved configuration.'
    Assert-ChromeTest ([IO.File]::GetLastWriteTimeUtc($path) -eq $beforeWrite) 'Try touched saved configuration.'
    Assert-ChromeTest ($script:startedProcesses.Count -eq 0) 'Try started a process.'
}

Invoke-ChromeTestCase 'try-applies-all-options-regardless-of-position' {
    Invoke-ChromeTestLaunch -Tokens @('work', '--proxy-server=http://old.example:7890', '--lang=zh-CN', 'https://saved.example', '-SetEnv', 'PW2401_CHROME_OVERRIDE=old', '-SetEnv', 'PW2401_CHROME_RETAIN=keep') | Out-Null
    $path = Get-ChromeTestConfigPath
    $before = [IO.File]::ReadAllBytes($path)
    $beforeWrite = [IO.File]::GetLastWriteTimeUtc($path)
    $beforeEntries = @(Get-ChildItem -LiteralPath $script:caseProfilePath -Recurse -Force | Select-Object -ExpandProperty FullName)
    $script:startedProcesses.Clear()
    $expectedOutput = $null
    $newProxy = '--proxy-server=http://new.example:8080'
    $newEnvironment = 'PW2401_CHROME_OVERRIDE=new'
    foreach ($tokens in @(
        @('work', '-Try', $newProxy, '-SetEnv', $newEnvironment, '--incognito'),
        @('work', $newProxy, '-tRy', '-SetEnv', $newEnvironment, '--incognito'),
        @('work', $newProxy, '-SetEnv', $newEnvironment, '--incognito', '-Try')
    )) {
        $plan = Get-ChromeTestPlan -Tokens $tokens
        $output = Invoke-ChromeTestLaunch -Tokens $tokens *>&1 | Out-String
        Assert-ChromeTest $plan.Try 'Try was not recognized at this argument position.'
        Assert-ChromeSequence @($plan.Config.arguments) @($newProxy, '--lang=zh-CN', 'https://saved.example', '--incognito') 'Preview did not merge new options with the saved arguments.'
        Assert-ChromeTest ($output.Contains($plan.CommandLine)) 'Preview output did not display the merged launch command.'
        Assert-ChromeTest (-not $plan.CommandLine.Contains('--proxy-server=http://old.example:7890')) 'Preview retained the superseded proxy.'
        $shownEnvironment = (Get-ChromeTestDisplayedEnvironment -Output $output -CommandLine $plan.CommandLine).Environment
        Assert-ChromeTest ($shownEnvironment['PW2401_CHROME_OVERRIDE'] -ceq 'new') 'Environment option after Try was not applied.'
        Assert-ChromeTest ($shownEnvironment['PW2401_CHROME_RETAIN'] -ceq 'keep') 'Preview lost an unrelated saved environment value.'
        if ($null -eq $expectedOutput) { $expectedOutput = $output }
        else { Assert-ChromeTest ($output -ceq $expectedOutput) 'Moving Try changed the final preview.' }
        Assert-ChromeSequence @([IO.File]::ReadAllBytes($path)) @($before) 'Try saved the previewed changes.'
        Assert-ChromeTest ([IO.File]::GetLastWriteTimeUtc($path) -eq $beforeWrite) 'Try touched the saved configuration.'
        Assert-ChromeSequence @(Get-ChildItem -LiteralPath $script:caseProfilePath -Recurse -Force | Select-Object -ExpandProperty FullName) $beforeEntries 'Try created additional files or directories.'
        Assert-ChromeTest ($script:startedProcesses.Count -eq 0) 'Try launched a process.'
    }
}

Invoke-ChromeTestCase 'reject-invalid-instance-and-options' {
    foreach ($name in @('../escape', 'nested/name', 'nested\name', '.', '..', 'with space', '实例', 'CON', 'nul', 'COM1', 'LPT9')) {
        Assert-ChromeFailure { Get-ChromeTestPlan -Tokens @($name) }
    }
    foreach ($tokens in @(
        @('work', '-SetEnv'), @('work', '-RemoveEnv'), @('work', '-ExecutablePath'),
        @('work', '-SetEnv', '=value'), @('work', '-SetEnv', 'MISSING_EQUALS'),
        @('work', '-RemoveEnv', 'INVALID=NAME'), @('work', '-Typo'),
        @('work', '-RemoveEnv', '-Try'), @('work', '-RemoveEnv', '-ClearArgs')
    )) {
        Assert-ChromeFailure { Get-ChromeTestPlan -Tokens $tokens }
    }
    Assert-ChromeTest (-not [IO.Directory]::Exists($script:caseProfilePath)) 'Invalid input created configuration directories.'
}

Invoke-ChromeTestCase 'reject-user-data-directory-override' {
    foreach ($argument in @('--user-data-dir=elsewhere', '--USER-DATA-DIR=elsewhere', '--user-data-dir', '-user-data-dir=elsewhere', '/user-data-dir=elsewhere', ' --user-data-dir=elsewhere', "`t/user-data-dir=elsewhere")) {
        Assert-ChromeFailure { Get-ChromeTestPlan -Tokens @('work', $argument) }
        $json = @{ executablePath = $null; arguments = @($argument); environment = @{} } | ConvertTo-Json
        Write-ChromeTestConfig $json
        Assert-ChromeFailure { Get-ChromeTestPlan -Tokens @('work') }
        [IO.File]::WriteAllText((Get-ChromeTestConfigPath), '{"executablePath":null,"arguments":[],"environment":{}}')
    }
    Assert-ChromeTest ($script:startedProcesses.Count -eq 0) 'Protected user directory override launched a process.'
}

Invoke-ChromeTestCase 'reject-corrupt-or-invalid-configuration' {
    foreach ($json in @(
        '{broken json', '[]', 'null',
        '{"executablePath":5,"arguments":[],"environment":{}}',
        '{"executablePath":null,"arguments":"--incognito","environment":{}}',
        '{"executablePath":null,"arguments":[5],"environment":{}}',
        '{"executablePath":null,"arguments":[null],"environment":{}}',
        '{"executablePath":null,"arguments":[],"environment":[]}',
        '{"executablePath":null,"arguments":[],"environment":{"NAME":5}}',
        '{"executablePath":null,"arguments":[],"environment":{"NAME":null}}',
        '{"executablePath":null,"arguments":[],"environment":{"BAD=NAME":"value"}}',
        '{"executablePath":null,"arguments":[],"environment":{},"Keys":"unknown-key"}'
    )) {
        Write-ChromeTestConfig $json
        Assert-ChromeFailure { Invoke-ChromeTestLaunch -Tokens @('work') }
        Assert-ChromeTest ([IO.File]::ReadAllText((Get-ChromeTestConfigPath)) -ceq $json) 'Invalid configuration was overwritten.'
    }
    Assert-ChromeTest ($script:startedProcesses.Count -eq 0) 'Invalid configuration started a process.'
}

Invoke-ChromeTestCase 'reject-invalid-executable-and-missing-discovery' {
    foreach ($path in @('relative.exe', (Join-Path $runRoot 'missing-chrome.exe'), $runRoot)) {
        Assert-ChromeFailure { Get-ChromeTestPlan -Tokens @('work', '-ExecutablePath', $path) }
    }
    function Get-ChromeExecutableCandidates { }
    Assert-ChromeFailure { Get-ChromeTestPlan -Tokens @('work') }
    Assert-ChromeTest (-not [IO.Directory]::Exists($script:caseProfilePath)) 'Failed executable resolution created a profile.'
}

Invoke-ChromeTestCase 'launch-failure-retains-saved-configuration' {
    function Start-ChromeProcess {
        param([Diagnostics.ProcessStartInfo]$StartInfo)
        throw 'Injected process launch failure.'
    }
    Assert-ChromeFailure { Invoke-ChromeTestLaunch -Tokens @('work', '--proxy-server=saved-before-failure') }
    $saved = [IO.File]::ReadAllText((Get-ChromeTestConfigPath)) | ConvertFrom-Json -AsHashtable
    Assert-ChromeSequence @($saved.arguments) @('--proxy-server=saved-before-failure') 'Launch failure discarded saved configuration.'
}

Invoke-ChromeTestCase 'save-failure-prevents-launch' {
    Invoke-ChromeTestLaunch -Tokens @('work', '--incognito') | Out-Null
    $script:startedProcesses.Clear()
    $path = Get-ChromeTestConfigPath
    $before = [IO.File]::ReadAllText($path)
    $lock = [IO.File]::Open($path, 'Open', 'Read', 'Read')
    try { Assert-ChromeFailure { Invoke-ChromeTestLaunch -Tokens @('work', '--proxy-server=must-not-start') } }
    finally { $lock.Dispose() }
    Assert-ChromeTest ($script:startedProcesses.Count -eq 0) 'Launcher started after configuration write failed.'
    Assert-ChromeTest ([IO.File]::ReadAllText($path) -ceq $before) 'Failed save damaged the previous configuration.'
    $leftovers = @(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($path)) -File -Force | Where-Object Name -NE 'launch.json')
    Assert-ChromeTest ($leftovers.Count -eq 0) 'Failed save left temporary configuration files.'
}

$reportPath = Join-Path $runRoot 'chrome-report.json'
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportPath -Encoding utf8
$failed = @($results | Where-Object Status -EQ 'Fail')
$passed = @($results | Where-Object Status -EQ 'Pass')
Write-Host "Chrome launcher tests: Pass $($passed.Count), Fail $($failed.Count). Report: $reportPath"
foreach ($failure in $failed) { Write-Host "$($failure.Name): $($failure.Message)" -ForegroundColor Red }
if ($failed.Count -gt 0) { exit 1 }

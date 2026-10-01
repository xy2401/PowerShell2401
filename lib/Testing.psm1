function New-PwTestDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Resolve-PwContainedPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw "$Label 必须是非空相对路径: $RelativePath"
    }

    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $candidate = [IO.Path]::GetFullPath((Join-Path $rootPath $RelativePath))
    $prefix = $rootPath + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label 超出允许目录: $RelativePath"
    }
    return $candidate
}

function Assert-PwAllowedKeys {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Value,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string]$Context
    )

    foreach ($key in $Value.Keys) {
        if ([string]$key -notin $Allowed) {
            throw "$Context 包含未知字段: $key"
        }
    }
}

function Get-PwDataItems {
    param(
        [AllowNull()][System.Collections.IDictionary]$Value,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if ($null -eq $Value -or -not $Value.Contains($Key) -or $null -eq $Value[$Key]) { return }
    foreach ($item in @($Value[$Key])) { Write-Output $item }
}

function Assert-PwRelativePattern {
    param([string]$Pattern, [string]$Context)

    if ([string]::IsNullOrWhiteSpace($Pattern) -or [IO.Path]::IsPathRooted($Pattern)) {
        throw "$Context 必须是非空相对路径模式: $Pattern"
    }
    $segments = $Pattern -split '[\\/]'
    if ($segments -contains '..') {
        throw "$Context 不允许使用父目录: $Pattern"
    }
}

function Get-PwTestDefinitions {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][object[]]$Catalog
    )

    $functionRoot = Join-Path $ProjectRoot 'functions'
    $catalogByName = @{}
    foreach ($command in $Catalog) { $catalogByName[$command.Name] = $command }

    foreach ($dataFile in Get-ChildItem -LiteralPath $functionRoot -Filter '*.psd1' -File) {
        $scriptPath = Join-Path $functionRoot "$($dataFile.BaseName).ps1"
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            throw "孤立测试文件，没有同名 PS1: $($dataFile.FullName)"
        }
        if (-not $catalogByName.ContainsKey($dataFile.BaseName)) {
            throw "测试文件不对应正式命令: $($dataFile.FullName)"
        }
    }

    $definitions = @()
    foreach ($command in $Catalog) {
        if ($command.Requires.Count -eq 0) { continue }

        $dataPath = Join-Path $functionRoot "$($command.Name).psd1"
        if (-not (Test-Path -LiteralPath $dataPath -PathType Leaf)) {
            throw "$($command.Name): 带有 Requires 但缺少同名测试文件 $dataPath"
        }

        try {
            $data = Import-PowerShellDataFile -LiteralPath $dataPath
        }
        catch {
            throw "无法解析测试文件 $dataPath：$($_.Exception.Message)"
        }
        if ($data -isnot [System.Collections.IDictionary]) {
            throw "$dataPath 的根对象必须是哈希表"
        }
        Assert-PwAllowedKeys -Value $data -Allowed @('SchemaVersion', 'Kind', 'Function', 'Cases') -Context $dataPath
        if ($data.SchemaVersion -ne 1) { throw "${dataPath}: 不支持的 SchemaVersion '$($data.SchemaVersion)'" }
        if ($data.Kind -ne 'Pw2401Test') { throw "${dataPath}: Kind 必须是 Pw2401Test" }
        if (-not [string]::Equals([string]$data.Function, $command.Name, [StringComparison]::Ordinal)) {
            throw "${dataPath}: Function '$($data.Function)' 必须与文件名 '$($command.Name)' 一致"
        }

        $cases = @($data.Cases)
        if ($cases.Count -eq 0) { throw "${dataPath}: Cases 至少需要一个测试用例" }
        $caseIds = @{}
        foreach ($case in $cases) {
            if ($case -isnot [System.Collections.IDictionary]) { throw "${dataPath}: 每个 case 必须是哈希表" }
            Assert-PwAllowedKeys -Value $case -Allowed @('Id', 'Example', 'Input', 'Expected') -Context "$dataPath case"
            if ([string]$case.Id -notmatch '^[a-z0-9][a-z0-9-]*$') {
                throw "${dataPath}: case Id '$($case.Id)' 只能使用小写字母、数字和连字符"
            }
            if ($caseIds.ContainsKey([string]$case.Id)) { throw "${dataPath}: case Id '$($case.Id)' 重复" }
            $caseIds[[string]$case.Id] = $true

            $example = @($command.Examples | Where-Object Id -CEQ ([string]$case.Example))
            if ($example.Count -ne 1) {
                throw "${dataPath}: case '$($case.Id)' 引用了不存在的 ExampleId '$($case.Example)'"
            }

            if ($null -ne $case.Input) {
                if ($case.Input -isnot [System.Collections.IDictionary]) { throw "${dataPath}: case '$($case.Id)' 的 Input 必须是哈希表" }
                Assert-PwAllowedKeys -Value $case.Input -Allowed @('Copy', 'Directories', 'TextFiles') -Context "$dataPath case '$($case.Id)' Input"
                foreach ($copy in @(Get-PwDataItems -Value $case.Input -Key 'Copy')) {
                    if ($copy -isnot [System.Collections.IDictionary]) { throw "${dataPath}: Input.Copy 项必须是哈希表" }
                    Assert-PwAllowedKeys -Value $copy -Allowed @('Source', 'Target') -Context "$dataPath case '$($case.Id)' Input.Copy"
                    [void](Resolve-PwContainedPath -Root $ProjectRoot -RelativePath ([string]$copy.Source) -Label 'Copy.Source')
                    [void](Resolve-PwContainedPath -Root (Join-Path $ProjectRoot 'target-path-validation') -RelativePath ([string]$copy.Target) -Label 'Copy.Target')
                }
                foreach ($directory in @(Get-PwDataItems -Value $case.Input -Key 'Directories')) {
                    [void](Resolve-PwContainedPath -Root (Join-Path $ProjectRoot 'target-path-validation') -RelativePath ([string]$directory) -Label 'Directories')
                }
                foreach ($textFile in @(Get-PwDataItems -Value $case.Input -Key 'TextFiles')) {
                    if ($textFile -isnot [System.Collections.IDictionary]) { throw "${dataPath}: Input.TextFiles 项必须是哈希表" }
                    Assert-PwAllowedKeys -Value $textFile -Allowed @('Path', 'Content') -Context "$dataPath case '$($case.Id)' Input.TextFiles"
                    [void](Resolve-PwContainedPath -Root (Join-Path $ProjectRoot 'target-path-validation') -RelativePath ([string]$textFile.Path) -Label 'TextFiles.Path')
                }
            }

            if ($case.Expected -isnot [System.Collections.IDictionary]) { throw "${dataPath}: case '$($case.Id)' 缺少 Expected 哈希表" }
            Assert-PwAllowedKeys -Value $case.Expected -Allowed @('ExitCode', 'StdoutContains', 'StdoutMatches', 'Exists', 'Missing', 'ExistsMatches', 'FileContains', 'Images', 'Media') -Context "$dataPath case '$($case.Id)' Expected"
            if (-not $case.Expected.Contains('ExitCode')) { throw "${dataPath}: case '$($case.Id)' 必须声明 Expected.ExitCode" }
            foreach ($path in @(Get-PwDataItems -Value $case.Expected -Key 'Exists') + @(Get-PwDataItems -Value $case.Expected -Key 'Missing')) {
                [void](Resolve-PwContainedPath -Root (Join-Path $ProjectRoot 'target-path-validation') -RelativePath ([string]$path) -Label 'Expected path')
            }
            foreach ($pattern in @(Get-PwDataItems -Value $case.Expected -Key 'ExistsMatches')) {
                Assert-PwRelativePattern -Pattern ([string]$pattern) -Context 'Expected.ExistsMatches'
            }
            foreach ($fileCheck in @(Get-PwDataItems -Value $case.Expected -Key 'FileContains')) {
                if ($fileCheck -isnot [System.Collections.IDictionary]) { throw "${dataPath}: Expected.FileContains 项必须是哈希表" }
                Assert-PwAllowedKeys -Value $fileCheck -Allowed @('Path', 'Contains') -Context "$dataPath case '$($case.Id)' Expected.FileContains"
                [void](Resolve-PwContainedPath -Root (Join-Path $ProjectRoot 'target-path-validation') -RelativePath ([string]$fileCheck.Path) -Label 'FileContains.Path')
            }

            foreach ($kind in @('Images', 'Media')) {
                foreach ($check in @(Get-PwDataItems -Value $case.Expected -Key $kind)) {
                    if ($check -isnot [System.Collections.IDictionary]) { throw "Expected.$kind 项必须是哈希表" }
                    $keys = if ($kind -eq 'Images') { @('Path', 'Width', 'Height', 'Orientation') } else { @('Path', 'Type', 'Width', 'Height', 'MinDuration') }
                    Assert-PwAllowedKeys -Value $check -Allowed $keys -Context "Expected.$kind"
                    [void](Resolve-PwContainedPath -Root (Join-Path $ProjectRoot 'target-path-validation') -RelativePath ([string]$check.Path) -Label "$kind.Path")
                    if ($kind -eq 'Media' -and 'ffprobe' -notin $command.Requires) {
                        throw "$dataPath 的 Media 断言要求命令声明 Requires: ffprobe"
                    }
                }
            }

            $definitions += [PSCustomObject]@{
                Command = $command
                Case = $case
                Example = $example[0]
                DataPath = $dataPath
            }
        }
    }
    return $definitions
}

function Initialize-PwDeclarativeInput {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$InputPath,
        [AllowNull()][System.Collections.IDictionary]$InputDefinition
    )

    New-PwTestDirectory $InputPath
    if ($null -eq $InputDefinition) { return }

    foreach ($relativePath in @(Get-PwDataItems -Value $InputDefinition -Key 'Directories')) {
        $destination = Resolve-PwContainedPath -Root $InputPath -RelativePath ([string]$relativePath) -Label 'Directories'
        New-PwTestDirectory $destination
    }
    foreach ($copy in @(Get-PwDataItems -Value $InputDefinition -Key 'Copy')) {
        $source = Resolve-PwContainedPath -Root $ProjectRoot -RelativePath ([string]$copy.Source) -Label 'Copy.Source'
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "测试素材不存在: $source" }
        $destination = Resolve-PwContainedPath -Root $InputPath -RelativePath ([string]$copy.Target) -Label 'Copy.Target'
        $parent = Split-Path -Path $destination -Parent
        New-PwTestDirectory $parent
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    foreach ($textFile in @(Get-PwDataItems -Value $InputDefinition -Key 'TextFiles')) {
        $destination = Resolve-PwContainedPath -Root $InputPath -RelativePath ([string]$textFile.Path) -Label 'TextFiles.Path'
        $parent = Split-Path -Path $destination -Parent
        New-PwTestDirectory $parent
        Set-Content -LiteralPath $destination -Value ([string]$textFile.Content) -Encoding utf8
    }
}

function Get-PwFixtureFingerprint {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $fixtureRoot = Join-Path $ProjectRoot 'tests\magika_basic'
    $entries = Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($fixtureRoot.Length).TrimStart('\', '/')
        "$relative|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($entries -join "`n"))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Get-PwFfmpegCapabilities {
    if ($null -eq $script:PwFfmpegCapabilities) {
        $encoders = (& ffmpeg -hide_banner -encoders 2>&1 | Out-String)
        $filters = (& ffmpeg -hide_banner -filters 2>&1 | Out-String)
        $script:PwFfmpegCapabilities = "$encoders`n$filters"
    }
    return $script:PwFfmpegCapabilities
}

function Test-PwNvencRuntime {
    if ($null -eq $script:PwNvencRuntimeAvailable) {
        & ffmpeg -hide_banner -loglevel error -f lavfi -i 'color=c=black:size=320x240:rate=1' -frames:v 1 -c:v av1_nvenc -f null - 2>$null | Out-Null
        $script:PwNvencRuntimeAvailable = $LASTEXITCODE -eq 0
    }
    return $script:PwNvencRuntimeAvailable
}

function Test-PwRequirements {
    param([string[]]$Requires)

    $missing = @()
    foreach ($requirement in $Requires) {
        if ($requirement -eq 'PowerShell') { continue }
        if ($requirement -in @('av1_nvenc', 'libsvtav1', 'libvmaf')) {
            if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
                $missing += 'ffmpeg'
                continue
            }
            $capabilities = Get-PwFfmpegCapabilities
            if ($capabilities -notmatch [regex]::Escape($requirement)) {
                $missing += $requirement
            }
            elseif ($requirement -eq 'av1_nvenc' -and -not (Test-PwNvencRuntime)) {
                $missing += $requirement
            }
            continue
        }
        if (-not (Get-Command $requirement -ErrorAction SilentlyContinue)) { $missing += $requirement }
    }
    return @($missing | Select-Object -Unique)
}

function Invoke-PwExampleProcess {
    param(
        [string]$EntryScript,
        [string]$WorkingDirectory,
        [string]$ExampleCode,
        [int]$TimeoutSeconds
    )

    $escapedEntry = $EntryScript.Replace("'", "''")
    $escapedWork = $WorkingDirectory.Replace("'", "''")
    $bootstrap = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new(`$false)
[Console]::InputEncoding = [Text.UTF8Encoding]::new(`$false)
function global:pw2401 {
    & '$escapedEntry' @args
}
Set-Location -LiteralPath '$escapedWork'
try {
$ExampleCode
}
catch {
    [Console]::Error.WriteLine("[POWERSHELL_ERROR] " + (`$_ | Out-String).Trim())
    exit 1
}
exit 0
"@

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrap))
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command pwsh -ErrorAction Stop).Source
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.CreateNoWindow = $true
    [void]$startInfo.ArgumentList.Add('-NoProfile')
    [void]$startInfo.ArgumentList.Add('-NonInteractive')
    [void]$startInfo.ArgumentList.Add('-EncodedCommand')
    [void]$startInfo.ArgumentList.Add($encoded)

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $started = Get-Date
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    $timedOut = -not $completed
    if ($timedOut) {
        try { $process.Kill($true) } catch { }
    }
    $process.WaitForExit()

    return [PSCustomObject]@{
        ExitCode = if ($timedOut) { $null } else { $process.ExitCode }
        StdOut = $stdoutTask.GetAwaiter().GetResult()
        StdErr = $stderrTask.GetAwaiter().GetResult()
        TimedOut = $timedOut
        Duration = [Math]::Round(((Get-Date) - $started).TotalSeconds, 3)
    }
}

function Write-PwCapturedStreams {
    param(
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)]$ProcessResult
    )

    Set-Content -LiteralPath (Join-Path $CaseRoot 'stdout.txt') -Value $ProcessResult.StdOut -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($ProcessResult.StdErr)) { return '' }

    $trimmed = $ProcessResult.StdErr.Trim()
    $fileName = if ($trimmed.StartsWith('#< CLIXML') -and $trimmed.EndsWith('</Objs>')) {
        'streams.clixml'
    }
    else {
        'streams.txt'
    }
    $content = if ($fileName -eq 'streams.clixml') {
        ConvertTo-PwIndentedCliXml -Text $ProcessResult.StdErr
    }
    else {
        $ProcessResult.StdErr
    }
    Set-Content -LiteralPath (Join-Path $CaseRoot $fileName) -Value $content -Encoding utf8
    return $fileName
}

function ConvertTo-PwIndentedCliXml {
    param([Parameter(Mandatory = $true)][string]$Text)

    try {
        $lineFeed = $Text.IndexOf("`n")
        if ($lineFeed -lt 0 -or -not $Text.TrimStart().StartsWith('#< CLIXML')) { return $Text }

        $xmlText = $Text.Substring($lineFeed + 1).Trim()
        $document = [Xml.XmlDocument]::new()
        $document.PreserveWhitespace = $false
        $document.LoadXml($xmlText)

        $settings = [Xml.XmlWriterSettings]::new()
        $settings.Indent = $true
        $settings.IndentChars = '  '
        $settings.NewLineChars = "`n"
        $settings.NewLineHandling = [Xml.NewLineHandling]::Replace
        $settings.OmitXmlDeclaration = $true

        $builder = [Text.StringBuilder]::new()
        $writer = [Xml.XmlWriter]::Create($builder, $settings)
        try { $document.Save($writer) }
        finally { $writer.Dispose() }
        return "#< CLIXML`n$builder"
    }
    catch {
        return $Text
    }
}

function New-PwAssertionResult {
    param([string]$Kind, [string]$Target, [bool]$Passed, [string]$Message)
    return [PSCustomObject]@{ Kind = $Kind; Target = $Target; Passed = $Passed; Message = $Message }
}

function Test-PwExpectedResults {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Expected,
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)]$ProcessResult
    )

    $assertions = @()
    $exitPassed = $ProcessResult.ExitCode -eq [int]$Expected.ExitCode
    $assertions += New-PwAssertionResult -Kind 'ExitCode' -Target ([string]$Expected.ExitCode) -Passed $exitPassed -Message "实际退出码: $($ProcessResult.ExitCode)"

    foreach ($text in @(Get-PwDataItems -Value $Expected -Key 'StdoutContains')) {
        $passed = $ProcessResult.StdOut.IndexOf([string]$text, [StringComparison]::OrdinalIgnoreCase) -ge 0
        $assertions += New-PwAssertionResult -Kind 'StdoutContains' -Target ([string]$text) -Passed $passed -Message $(if ($passed) { '已找到' } else { '标准输出中未找到' })
    }
    foreach ($pattern in @(Get-PwDataItems -Value $Expected -Key 'StdoutMatches')) {
        $passed = [regex]::IsMatch($ProcessResult.StdOut, [string]$pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $assertions += New-PwAssertionResult -Kind 'StdoutMatches' -Target ([string]$pattern) -Passed $passed -Message $(if ($passed) { '已匹配' } else { '标准输出不匹配' })
    }
    foreach ($relativePath in @(Get-PwDataItems -Value $Expected -Key 'Exists')) {
        $path = Resolve-PwContainedPath -Root $CaseRoot -RelativePath ([string]$relativePath) -Label 'Expected.Exists'
        $passed = Test-Path -LiteralPath $path
        $assertions += New-PwAssertionResult -Kind 'Exists' -Target ([string]$relativePath) -Passed $passed -Message $(if ($passed) { '路径存在' } else { '路径不存在' })
    }
    foreach ($relativePath in @(Get-PwDataItems -Value $Expected -Key 'Missing')) {
        $path = Resolve-PwContainedPath -Root $CaseRoot -RelativePath ([string]$relativePath) -Label 'Expected.Missing'
        $passed = -not (Test-Path -LiteralPath $path)
        $assertions += New-PwAssertionResult -Kind 'Missing' -Target ([string]$relativePath) -Passed $passed -Message $(if ($passed) { '路径不存在' } else { '路径仍然存在' })
    }
    $existsMatches = @(Get-PwDataItems -Value $Expected -Key 'ExistsMatches')
    if ($existsMatches.Count -gt 0) {
        $allPaths = @(Get-ChildItem -LiteralPath $CaseRoot -Recurse -Force | ForEach-Object {
            $_.FullName.Substring($CaseRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        })
        foreach ($pattern in $existsMatches) {
            $normalized = ([string]$pattern) -replace '\\', '/'
            $passed = @($allPaths | Where-Object { $_ -like $normalized }).Count -gt 0
            $assertions += New-PwAssertionResult -Kind 'ExistsMatches' -Target ([string]$pattern) -Passed $passed -Message $(if ($passed) { '找到匹配路径' } else { '没有匹配路径' })
        }
    }
    foreach ($fileCheck in @(Get-PwDataItems -Value $Expected -Key 'FileContains')) {
        $path = Resolve-PwContainedPath -Root $CaseRoot -RelativePath ([string]$fileCheck.Path) -Label 'Expected.FileContains'
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        $content = if ($exists) { Get-Content -LiteralPath $path -Raw } else { '' }
        foreach ($text in @(Get-PwDataItems -Value $fileCheck -Key 'Contains')) {
            $passed = $exists -and $content.IndexOf([string]$text, [StringComparison]::OrdinalIgnoreCase) -ge 0
            $assertions += New-PwAssertionResult -Kind 'FileContains' -Target "$($fileCheck.Path) :: $text" -Passed $passed -Message $(if (-not $exists) { '文件不存在' } elseif ($passed) { '已找到' } else { '文件中未找到' })
        }
    }

    foreach ($kind in @('Images', 'Media')) {
        foreach ($check in @(Get-PwDataItems -Value $Expected -Key $kind)) {
            $path = Resolve-PwContainedPath -Root $CaseRoot -RelativePath ([string]$check.Path) -Label "Expected.$kind"
            $image = $null
            try {
                if ($kind -eq 'Images') {
                    Add-Type -AssemblyName System.Drawing
                    $image = [Drawing.Image]::FromFile($path)
                    $orientation = if ($image.PropertyIdList -contains 274) { [BitConverter]::ToInt16($image.GetPropertyItem(274).Value, 0) } else { 1 }
                    $actual = @{ Width = $image.Width; Height = $image.Height; Orientation = $orientation }
                }
                else {
                    $media = Get-MediaInfo -Path $path
                    if (-not $media.HasVideo) { throw "无法读取视频流: $path" }
                    $actual = @{ Type = $media.Type; Width = $media.Width; Height = $media.Height; MinDuration = $media.Duration }
                }
                foreach ($key in $check.Keys | Where-Object { $_ -ne 'Path' }) {
                    $passed = if ($key -eq 'MinDuration') { $media.DurationKnown -and $actual[$key] -ge $check[$key] } else { $actual[$key] -eq $check[$key] }
                    $assertions += New-PwAssertionResult -Kind "$kind.$key" -Target ([string]$check.Path) -Passed $passed -Message "预期 $($check[$key])，实际 $($actual[$key])"
                }
            }
            catch {
                $assertions += New-PwAssertionResult -Kind $kind -Target ([string]$check.Path) -Passed $false -Message $_.Exception.Message
            }
            finally {
                if ($null -ne $image) { $image.Dispose() }
            }
        }
    }

    return [PSCustomObject]@{
        Passed = @($assertions | Where-Object { -not $_.Passed }).Count -eq 0
        Assertions = $assertions
    }
}

function Write-PwTestReport {
    param([object[]]$Results, [string]$RunRoot, [bool]$External)

    $summary = [ordered]@{
        Total = $Results.Count
        Pass = @($Results | Where-Object Status -eq 'Pass').Count
        Fail = @($Results | Where-Object Status -eq 'Fail').Count
        Skip = @($Results | Where-Object Status -eq 'Skip').Count
    }
    [ordered]@{
        GeneratedAt = (Get-Date).ToString('o')
        External = $External
        Summary = $summary
        Results = $Results
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $RunRoot 'report.json') -Encoding utf8

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# pw2401 示例测试报告')
    $lines.Add('')
    $lines.Add("- 时间：$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
    $lines.Add("- 外部依赖测试：$(if ($External) { '启用' } else { '未启用' })")
    $lines.Add("- 汇总：Pass $($summary.Pass)，Fail $($summary.Fail)，Skip $($summary.Skip)")
    $lines.Add('')
    $lines.Add('| 命令 | ExampleId | CaseId | 分组 | 依赖 | 状态 | 耗时(秒) | 退出码 | 说明 |')
    $lines.Add('|---|---|---|---|---|---|---:|---:|---|')
    foreach ($result in $Results) {
        $message = ([string]$result.Message) -replace '\|', '\|' -replace "`r?`n", '<br>'
        $requires = (@($result.Requires) -join ', ') -replace '\|', '\|'
        $exitCode = if ($null -eq $result.ExitCode) { '—' } else { [string]$result.ExitCode }
        $lines.Add("| $($result.Command) | $($result.ExampleId) | $($result.CaseId) | $($result.Group) | $requires | $($result.Status) | $($result.Duration) | $exitCode | $message |")
    }
    foreach ($result in @($Results | Where-Object { -not [string]::IsNullOrWhiteSpace($_.CasePath) })) {
        $lines.Add('')
        $lines.Add("## $($result.Command) / $($result.ExampleId) / $($result.CaseId)")
        $lines.Add('')
        $lines.Add("- 状态：$($result.Status)")
        $lines.Add("- Case：``$($result.CasePath)``")
        if (-not [string]::IsNullOrWhiteSpace($result.StreamFile)) {
            $lines.Add("- 原始流：``$($result.StreamFile)``")
        }
        $failedAssertions = @($result.Assertions | Where-Object { -not $_.Passed })
        if ($failedAssertions.Count -gt 0) {
            $lines.Add('- 失败断言：')
            foreach ($assertion in $failedAssertions) {
                $lines.Add("  - $($assertion.Kind) ``$($assertion.Target)``：$($assertion.Message)")
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($result.ErrorOutput)) {
            $lines.Add('')
            $lines.Add('```text')
            $lines.Add($result.ErrorOutput.Trim())
            $lines.Add('```')
        }
    }
    ($lines -join "`n") + "`n" | Set-Content -LiteralPath (Join-Path $RunRoot 'report.md') -Encoding utf8
}

function Invoke-PwExampleTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$WorkDir,
        [switch]$External
    )

    $catalog = @(Get-PwCommandCatalog -ProjectRoot $ProjectRoot)
    $helpIssues = @(Test-PwCommandHelp -Catalog $catalog)
    if ($helpIssues.Count -gt 0) { throw "命令帮助校验失败：`n - $($helpIssues -join "`n - ")" }
    $definitions = @(Get-PwTestDefinitions -ProjectRoot $ProjectRoot -Catalog $catalog)

    $targetRoot = Join-Path ([IO.Path]::GetFullPath($WorkDir)) 'target\pw2401-tests'
    $runId = "$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')-$PID"
    $runRoot = Join-Path $targetRoot "runs\$runId"
    $casesRoot = Join-Path $runRoot 'cases'
    New-PwTestDirectory $casesRoot

    $fingerprintBefore = Get-PwFixtureFingerprint -ProjectRoot $ProjectRoot
    $entryScript = Join-Path $ProjectRoot 'pw2401.ps1'
    $results = @()

    foreach ($definition in $definitions) {
        $command = $definition.Command
        $case = $definition.Case
        $example = $definition.Example
        $isPowerShell = $command.Requires.Count -eq 1 -and $command.Requires[0] -eq 'PowerShell'
        $group = if ($isPowerShell) { 'PowerShell' } else { 'External' }

        if (-not $isPowerShell -and -not $External) {
            $results += [PSCustomObject]@{
                Command = $command.Name; ExampleId = $example.Id; CaseId = $case.Id; Group = $group
                Requires = @($command.Requires); Status = 'Skip'; Duration = 0; ExitCode = $null
                TimedOut = $false; PowerShellError = $false; Message = '未启用 -External'
                Assertions = @(); ErrorOutput = ''; StreamFile = ''; CasePath = ''
            }
            continue
        }

        $missing = @(Test-PwRequirements -Requires $command.Requires)
        if ($missing.Count -gt 0) {
            $results += [PSCustomObject]@{
                Command = $command.Name; ExampleId = $example.Id; CaseId = $case.Id; Group = $group
                Requires = @($command.Requires); Status = 'Skip'; Duration = 0; ExitCode = $null
                TimedOut = $false; PowerShellError = $false; Message = "缺少依赖: $($missing -join ', ')"
                Assertions = @(); ErrorOutput = ''; StreamFile = ''; CasePath = ''
            }
            continue
        }

        $caseRoot = Join-Path (Join-Path $casesRoot $command.Name) ([string]$case.Id)
        $inputPath = Join-Path $caseRoot 'input'
        try {
            Initialize-PwDeclarativeInput -ProjectRoot $ProjectRoot -InputPath $inputPath -InputDefinition $case.Input
            $timeout = if ($isPowerShell) { 60 } else { 300 }
            $processResult = Invoke-PwExampleProcess -EntryScript $entryScript -WorkingDirectory $inputPath -ExampleCode $example.Code -TimeoutSeconds $timeout
            $streamFile = Write-PwCapturedStreams -CaseRoot $caseRoot -ProcessResult $processResult

            $combined = "$($processResult.StdOut)`n$($processResult.StdErr)"
            $hasErrorLog = $combined -match '(?i)\[ERROR\]'
            $hasPowerShellError = $processResult.StdErr -match '\[POWERSHELL_ERROR\]'
            $assertionResult = Test-PwExpectedResults -Expected $case.Expected -CaseRoot $caseRoot -ProcessResult $processResult
            $passed = -not $processResult.TimedOut -and -not $hasErrorLog -and -not $hasPowerShellError -and $assertionResult.Passed
            $messages = @()
            if ($processResult.TimedOut) { $messages += "超过 $timeout 秒" }
            if ($hasPowerShellError) { $messages += '出现 PowerShell ErrorRecord' }
            if ($hasErrorLog) { $messages += '输出包含 [ERROR]' }
            $failedCount = @($assertionResult.Assertions | Where-Object { -not $_.Passed }).Count
            if ($failedCount -gt 0) { $messages += "$failedCount 项断言失败" }
            if ($messages.Count -eq 0) { $messages += "$($assertionResult.Assertions.Count) 项断言通过" }
            $failureDetails = @($assertionResult.Assertions | Where-Object { -not $_.Passed } | ForEach-Object { "$($_.Kind) $($_.Target): $($_.Message)" })
            $errorOutput = if ($passed) { '' } else { (@($processResult.StdErr.Trim()) + $failureDetails | Where-Object { $_ }) -join "`n" }

            $results += [PSCustomObject]@{
                Command = $command.Name; ExampleId = $example.Id; CaseId = $case.Id; Group = $group
                Requires = @($command.Requires); Status = if ($passed) { 'Pass' } else { 'Fail' }
                Duration = $processResult.Duration; ExitCode = $processResult.ExitCode
                TimedOut = $processResult.TimedOut; PowerShellError = $hasPowerShellError
                Message = $messages -join '；'; Assertions = @($assertionResult.Assertions)
                ErrorOutput = $errorOutput; StreamFile = $streamFile; CasePath = [IO.Path]::GetFullPath($caseRoot)
            }
        }
        catch {
            New-PwTestDirectory $caseRoot
            $errorText = $_ | Out-String
            Set-Content -LiteralPath (Join-Path $caseRoot 'setup-error.txt') -Value $errorText -Encoding utf8
            $results += [PSCustomObject]@{
                Command = $command.Name; ExampleId = $example.Id; CaseId = $case.Id; Group = $group
                Requires = @($command.Requires); Status = 'Fail'; Duration = 0; ExitCode = $null
                TimedOut = $false; PowerShellError = $false; Message = '测试准备、执行或断言失败'
                Assertions = @(); ErrorOutput = $errorText.Trim(); StreamFile = ''; CasePath = [IO.Path]::GetFullPath($caseRoot)
            }
        }
    }

    $fingerprintAfter = Get-PwFixtureFingerprint -ProjectRoot $ProjectRoot
    if ($fingerprintBefore -ne $fingerprintAfter) {
        $results += [PSCustomObject]@{
            Command = 'magika_basic'; ExampleId = 'read-only-fingerprint'; CaseId = 'sha256'; Group = 'Isolation'
            Requires = @(); Status = 'Fail'; Duration = 0; ExitCode = $null; TimedOut = $false
            PowerShellError = $false; Message = '原始测试素材发生变化'; Assertions = @()
            ErrorOutput = '测试前后 SHA256 指纹不同'; StreamFile = ''; CasePath = (Join-Path $ProjectRoot 'tests\magika_basic')
        }
    }

    Write-PwTestReport -Results $results -RunRoot $runRoot -External ([bool]$External)
    return [PSCustomObject]@{
        RunPath = [IO.Path]::GetFullPath($runRoot)
        Results = $results
        PassCount = @($results | Where-Object Status -eq 'Pass').Count
        FailCount = @($results | Where-Object Status -eq 'Fail').Count
        SkipCount = @($results | Where-Object Status -eq 'Skip').Count
    }
}

Export-ModuleMember -Function Invoke-PwExampleTests

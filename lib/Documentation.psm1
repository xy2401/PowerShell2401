function ConvertTo-PwMarkdownText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    return ($Text.Trim() -replace '\|', '\|')
}

function ConvertFrom-PwHelpExample {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][int]$Index
    )

    $lines = @($Text -replace "`r`n", "`n" -split "`n")
    while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[0])) { $lines = @($lines | Select-Object -Skip 1) }
    while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[-1])) { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }

    $separator = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) {
            $separator = $i
            break
        }
    }

    if ($separator -lt 0) {
        $codeLines = @($lines)
        $description = ""
    }
    else {
        $codeLines = @($lines | Select-Object -First $separator)
        $description = (@($lines | Select-Object -Skip ($separator + 1)) -join "`n").Trim()
    }

    $id = ""
    if ($codeLines.Count -gt 0 -and $codeLines[0] -match '^\s*#\s*ExampleId\s*:\s*(\S+)\s*$') {
        $id = $matches[1]
        $codeLines = @($codeLines | Select-Object -Skip 1)
    }
    $code = ($codeLines -join "`n").Trim()

    [PSCustomObject]@{
        Index       = $Index
        Id          = $id
        Code        = $code
        Description = $description
    }
}

function Get-PwParameterDescription {
    param($HelpContent, [string]$Name)

    if ($null -eq $HelpContent -or $null -eq $HelpContent.Parameters) { return "" }
    foreach ($entry in $HelpContent.Parameters.GetEnumerator()) {
        if ([string]::Equals([string]$entry.Key, $Name, [StringComparison]::OrdinalIgnoreCase)) {
            return ([string]$entry.Value).Trim()
        }
    }
    return ""
}

function Get-PwCommandCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$IncludeDebug
    )

    $functionRoot = Join-Path $ProjectRoot "functions"
    $files = Get-ChildItem -LiteralPath $functionRoot -Filter "*.ps1" -File | Sort-Object BaseName
    if (-not $IncludeDebug) {
        $files = @($files | Where-Object {
            $_.BaseName -notlike "debug-*" -and $_.BaseName -notlike "sys-debug-*"
        })
    }

    foreach ($file in $files) {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName,
            [ref]$tokens,
            [ref]$parseErrors
        )
        if ($parseErrors.Count -gt 0) {
            throw "无法解析 $($file.FullName): $($parseErrors[0].Message)"
        }

        $help = $ast.GetHelpContent()
        $parameters = @()
        if ($null -ne $ast.ParamBlock) {
            foreach ($parameterAst in $ast.ParamBlock.Parameters) {
                $name = $parameterAst.Name.VariablePath.UserPath
                $typeConstraint = $parameterAst.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.Language.TypeConstraintAst] } |
                    Select-Object -First 1
                $parameterAttribute = $parameterAst.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.Language.AttributeAst] -and $_.TypeName.Name -eq "Parameter" } |
                    Select-Object -First 1
                $mandatory = $false
                if ($null -ne $parameterAttribute) {
                    $mandatoryArgument = $parameterAttribute.NamedArguments |
                        Where-Object ArgumentName -eq "Mandatory" |
                        Select-Object -First 1
                    $mandatory = $null -ne $mandatoryArgument -and $mandatoryArgument.Argument.Extent.Text -match '\$true'
                }

                $parameters += [PSCustomObject]@{
                    Name        = $name
                    Type        = if ($null -ne $typeConstraint) { $typeConstraint.TypeName.FullName } else { "object" }
                    Mandatory   = $mandatory
                    Default     = if ($null -ne $parameterAst.DefaultValue) { $parameterAst.DefaultValue.Extent.Text } else { "" }
                    Description = Get-PwParameterDescription -HelpContent $help -Name $name
                }
            }
        }

        $examples = @()
        $exampleIndex = 0
        if ($null -ne $help) {
            foreach ($rawExample in @($help.Examples)) {
                $exampleIndex++
                $examples += ConvertFrom-PwHelpExample -Text ([string]$rawExample) -Index $exampleIndex
            }
        }

        $notes = if ($null -ne $help) { ([string]$help.Notes).Trim() } else { "" }
        $requires = @()
        if ($notes -match '(?im)^\s*Requires\s*:\s*(.+?)\s*$') {
            $requires = @($matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
        $visibleNotes = (($notes -split "`r?`n") | Where-Object { $_ -notmatch '^\s*Requires\s*:' }) -join "`n"

        [PSCustomObject]@{
            Name        = $file.BaseName
            Path        = $file.FullName
            Synopsis    = if ($null -ne $help) { ([string]$help.Synopsis).Trim() } else { "" }
            Description = if ($null -ne $help) { ([string]$help.Description).Trim() } else { "" }
            Notes       = $visibleNotes.Trim()
            Requires    = $requires
            Parameters  = $parameters
            Examples    = $examples
        }
    }
}

function Test-PwCommandHelp {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$Catalog)

    $issues = @()
    foreach ($command in $Catalog) {
        if ([string]::IsNullOrWhiteSpace($command.Synopsis)) {
            $issues += "$($command.Name): 缺少 .SYNOPSIS"
        }
        if ([string]::IsNullOrWhiteSpace($command.Description)) {
            $issues += "$($command.Name): 缺少 .DESCRIPTION"
        }
        if ($command.Examples.Count -eq 0) {
            $issues += "$($command.Name): 缺少 .EXAMPLE"
        }
        $exampleIds = @{}
        foreach ($example in $command.Examples) {
            if ([string]::IsNullOrWhiteSpace($example.Id)) {
                $issues += "$($command.Name): 示例 $($example.Index) 缺少 # ExampleId: 标记"
                continue
            }
            if ($example.Id -notmatch '^[a-z0-9][a-z0-9-]*$') {
                $issues += "$($command.Name): ExampleId '$($example.Id)' 只能使用小写字母、数字和连字符"
            }
            if ($exampleIds.ContainsKey($example.Id)) {
                $issues += "$($command.Name): ExampleId '$($example.Id)' 重复"
            }
            else {
                $exampleIds[$example.Id] = $true
            }
            if ([string]::IsNullOrWhiteSpace($example.Code)) {
                $issues += "$($command.Name): ExampleId '$($example.Id)' 缺少可执行命令"
            }
        }
        foreach ($parameter in $command.Parameters) {
            if ([string]::IsNullOrWhiteSpace($parameter.Description)) {
                $issues += "$($command.Name): 参数 $($parameter.Name) 缺少 .PARAMETER 说明"
            }
        }
    }
    return $issues
}

function ConvertTo-PwCommandMarkdown {
    param([Parameter(Mandatory = $true)]$Command)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("<!-- Generated from functions/$($Command.Name).ps1. Do not edit directly. -->")
    $lines.Add("")
    $lines.Add("# $($Command.Name)")
    $lines.Add("")
    $lines.Add($Command.Synopsis)
    $lines.Add("")
    $lines.Add("## 用法")
    $lines.Add("")
    $syntaxParts = @("pw2401", $Command.Name)
    foreach ($parameter in $Command.Parameters) {
        $part = "-$($parameter.Name) <$($parameter.Type)>"
        if (-not $parameter.Mandatory) { $part = "[$part]" }
        $syntaxParts += $part
    }
    $lines.Add('```powershell')
    $lines.Add($syntaxParts -join " ")
    $lines.Add('```')
    $lines.Add("")
    $lines.Add("## 说明")
    $lines.Add("")
    $lines.Add($Command.Description)

    if ($Command.Parameters.Count -gt 0) {
        $lines.Add("")
        $lines.Add("## 参数")
        $lines.Add("")
        $lines.Add("| 参数 | 类型 | 必需 | 默认值 | 说明 |")
        $lines.Add("|---|---|---:|---|---|")
        foreach ($parameter in $Command.Parameters) {
            $defaultText = if ([string]::IsNullOrWhiteSpace($parameter.Default)) { "—" } else { ConvertTo-PwMarkdownText $parameter.Default }
            $description = (ConvertTo-PwMarkdownText $parameter.Description) -replace "`r?`n", "<br>"
            $lines.Add("| ``-$($parameter.Name)`` | ``$($parameter.Type)`` | $(if ($parameter.Mandatory) { '是' } else { '否' }) | $defaultText | $description |")
        }
    }

    if ($Command.Requires.Count -gt 0) {
        $lines.Add("")
        $lines.Add("## 依赖")
        $lines.Add("")
        $lines.Add($Command.Requires -join ", ")
    }

    $lines.Add("")
    $lines.Add("## 示例")
    foreach ($example in $Command.Examples) {
        $lines.Add("")
        $lines.Add("### 示例 $($example.Index)：$($example.Id)")
        $lines.Add("")
        $lines.Add('```powershell')
        $lines.Add($example.Code)
        $lines.Add('```')
        if (-not [string]::IsNullOrWhiteSpace($example.Description)) {
            $lines.Add("")
            $lines.Add($example.Description)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Command.Notes)) {
        $lines.Add("")
        $lines.Add("## 备注")
        $lines.Add("")
        $lines.Add($Command.Notes)
    }

    return ($lines -join "`n") + "`n"
}

function New-PwDocumentation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$OutputPath = (Join-Path $ProjectRoot "docs")
    )

    $catalog = @(Get-PwCommandCatalog -ProjectRoot $ProjectRoot)
    $issues = @(Test-PwCommandHelp -Catalog $catalog)
    if ($issues.Count -gt 0) {
        throw "命令帮助校验失败：`n - $($issues -join "`n - ")"
    }

    $commandsPath = Join-Path $OutputPath "commands"
    New-Item -ItemType Directory -Path $commandsPath -Force | Out-Null

    $expectedFiles = @()
    foreach ($command in $catalog) {
        $documentPath = Join-Path $commandsPath "$($command.Name).md"
        ConvertTo-PwCommandMarkdown -Command $command | Set-Content -LiteralPath $documentPath -Encoding utf8 -NoNewline
        $expectedFiles += $documentPath
    }

    Get-ChildItem -LiteralPath $commandsPath -Filter "*.md" -File | ForEach-Object {
        if ($_.FullName -notin $expectedFiles) {
            $firstLine = Get-Content -LiteralPath $_.FullName -TotalCount 1
            if ($firstLine -like "<!-- Generated from functions/*") {
                Remove-Item -LiteralPath $_.FullName -Force
            }
        }
    }

    $index = [System.Collections.Generic.List[string]]::new()
    $index.Add("<!-- Generated from functions/*.ps1. Do not edit directly. -->")
    $index.Add("")
    $index.Add("# pw2401 命令文档")
    $index.Add("")
    $index.Add("以下文档由各命令的 PowerShell 注释帮助自动生成。")
    $index.Add("")
    $index.Add("| 命令 | 说明 | 依赖 |")
    $index.Add("|---|---|---|")
    foreach ($command in $catalog) {
        $dependency = if ($command.Requires.Count -gt 0) { $command.Requires -join ", " } else { "仅文档" }
        $index.Add("| [$($command.Name)](commands/$($command.Name).md) | $(ConvertTo-PwMarkdownText $command.Synopsis) | $(ConvertTo-PwMarkdownText $dependency) |")
    }
    ($index -join "`n") + "`n" | Set-Content -LiteralPath (Join-Path $OutputPath "README.md") -Encoding utf8 -NoNewline

    return [PSCustomObject]@{
        OutputPath   = (Resolve-Path -LiteralPath $OutputPath).Path
        CommandCount = $catalog.Count
    }
}

Export-ModuleMember -Function Get-PwCommandCatalog, Test-PwCommandHelp, New-PwDocumentation

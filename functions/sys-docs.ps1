<#
.SYNOPSIS
    根据 functions 目录中的 PowerShell 注释帮助生成 Markdown 文档。

.DESCRIPTION
    校验所有正式命令的注释帮助，并在项目 docs 目录中生成命令索引和独立命令页面。
    文档完全来源于脚本中的 .SYNOPSIS、.DESCRIPTION、.PARAMETER、.EXAMPLE 和 .NOTES。

.EXAMPLE
    # ExampleId: generate-docs
    pw2401 docs

    重新生成全部命令文档。

#>
param()

$runtime = $global:GlobalConfig.runtime
$result = New-PwDocumentation -ProjectRoot $runtime.ProjectRoot
Write-LogMessage "已生成 $($result.CommandCount) 个命令文档：$($result.OutputPath)" -Level Success

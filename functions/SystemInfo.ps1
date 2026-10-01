<#
.SYNOPSIS
    显示 Windows 操作系统、处理器和内存信息。

.DESCRIPTION
    通过 CIM 查询当前 Windows 系统的版本、CPU 名称及物理内存总量，并输出格式化快照。

.EXAMPLE
    # ExampleId: system-summary
    pw2401 SystemInfo

    显示当前计算机的系统信息。

.NOTES
    Requires: PowerShell
#>
[CmdletBinding()]
param()

Write-LogMessage "正在获取系统快照..." -Level Info

$os = $null
$cpu = $null
$ram = $null
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop | Select-Object Caption, Version
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object Name
    $ram = Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop |
        Measure-Object Capacity -Sum |
        ForEach-Object { "$([Math]::Round($_.Sum / 1GB, 2)) GB" }
}
catch {
    Write-LogMessage "无法读取完整 CIM 系统信息，将使用 Unknown：$($_.Exception.Message)" -Level Warning
}

$snapshot = [PSCustomObject]@{
    OS      = if ($os) { $os.Caption } else { "Unknown" }
    Version = if ($os) { $os.Version } else { "Unknown" }
    CPU     = if ($cpu) { $cpu.Name } else { "Unknown" }
    RAM     = if ($ram) { $ram } else { "Unknown" }
}

$snapshot | Format-List

[CmdletBinding()]
param()

Log-Message "正在获取系统快照..." -Level Info

$os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version
$cpu = Get-CimInstance Win32_Processor | Select-Object Name
$ram = Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum | ForEach-Object { "$([Math]::Round($_.Sum / 1GB, 2)) GB" }

$snapshot = [PSCustomObject]@{
    OS      = if ($os) { $os.Caption } else { "Unknown" }
    Version = if ($os) { $os.Version } else { "Unknown" }
    CPU     = if ($cpu) { $cpu.Name } else { "Unknown" }
    RAM     = if ($ram) { $ram } else { "Unknown" }
}

$snapshot | Format-List

<#
.SYNOPSIS
    初始化全局配置与运行时环境上下文。
#>
function Get-GlobalConfig {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        
        [string[]]$Arguments = @()
    )

    # 1. 读取配置文件
    $configPath = Join-Path $ProjectRoot "config.json"
    if (Test-Path -LiteralPath $configPath) {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    }
    else {
        Log-Message "config.json not found ! " -Level Warning
        $config = [PSCustomObject]@{
            extensions = [PSCustomObject]@{ image = @(); video = @() }
        }
    }

    # 2. 计算实时运行时路径信息
    $currentDir = (Get-Location).Path
    $currentDirName = Split-Path $currentDir -Leaf
    $parentDir = Split-Path $currentDir -Parent
    $suffix = "target" #
    $targetDirName = "${currentDirName}.$suffix"
    $targetDir = Join-Path $parentDir $targetDirName

    # 3. 组装或更新 runtime 基础对象
    $runtimeBase = @{
        IsDebug       = $false
        LogFile       = $null
        LogFilePath   = $null
        WorkDir       = $currentDir
        WorkDirName   = $currentDirName
        ParentDir     = $parentDir
        TargetDir     = $targetDir
        TargetDirName = $targetDirName
        ProjectRoot   = $ProjectRoot 
    }

    # 1. 确保 runtime 容器存在 (如果为 null 则初始化为空对象)
    if ($null -eq $config.runtime) {
        $config | Add-Member -NotePropertyMembers @{ runtime = [PSCustomObject]@{} }
    }
 
    foreach ($key in $runtimeBase.Keys) {
        $config.runtime.$key = $runtimeBase[$key]
    }
   
 
    if ($Arguments -contains "-Debug") { $config.runtime.IsDebug = $true }

    return $config
}

<#
.SYNOPSIS
    基于传入的后缀更新运行时环境的目标目录 (TargetDir) 和 目标目录名 (TargetDirName)。
#>
function Update-Target {
    param (
        [string]$suffix
    )

    $runtime = $global:GlobalConfig.runtime

    # 计算新的目标目录名字与完整路径
    $targetDirName = "$($runtime.WorkDirName)$suffix"
    $targetDir = Join-Path -Path $runtime.ParentDir -ChildPath $targetDirName

    $runtime.TargetDirName = $targetDirName
    $runtime.TargetDir = $targetDir

    Log-Message "Update-Target: TargetDirName=$targetDirName" -Level Info
}

Export-ModuleMember -Function Get-GlobalConfig, Update-Target

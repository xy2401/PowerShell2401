[CmdletBinding()]
param()

$EnvVarName = "pw2401_home"
# 获取持久化的环境变量值
$CurrentHome = [Environment]::GetEnvironmentVariable($EnvVarName, [EnvironmentVariableTarget]::User)
 
$runtime = $global:GlobalConfig.runtime
$TargetHome = $runtime.ProjectRoot

if ($null -ne $CurrentHome) {
    # --- Uninstall ---
    Log-Message "Installation detected. Uninstalling..." -Level Warning

    # 1. 从用户注册表的 Path 中移除
    $Path = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
    Log-Message "Old User PATH (Registry): $Path" -Level Info
    $PathEntries = $Path -split ";" | Where-Object { 
        $_ -ne "%$EnvVarName%" -and $_ -ne "%$EnvVarName%\scripts" -and $_ -ne $CurrentHome -and $_ -ne (Join-Path $CurrentHome "scripts")
    }
    $NewPath = ($PathEntries | Where-Object { $_ -ne "" }) -join ";"
    
    if ($Path -ne $NewPath) {
        Log-Message "Updating User PATH (Registry) to: $NewPath" -Level Info
        [Environment]::SetEnvironmentVariable("Path", $NewPath, [EnvironmentVariableTarget]::User)
    }

    # 2. 从注册表中彻底删除环境变量
    [Environment]::SetEnvironmentVariable($EnvVarName, [NullString]::Value, [EnvironmentVariableTarget]::User) 
    

    # 3. 清理当前会话 (Session) 中的变量，使其立即“消失”
    if (Test-Path "Env:\$EnvVarName") {
        Remove-Item "Env:\$EnvVarName"
    }
    
    # 4. (可选) 同步清理当前会话 de $env:Path，避免残留
    $env:Path = ($env:Path -split ";" | Where-Object { 
        $_ -ne $CurrentHome -and $_ -ne (Join-Path $CurrentHome "scripts")
    }) -join ";"

    Log-Message "Successfully removed '$EnvVarName' and cleaned up PATH." -Level Success
}
else {
    # --- Install ---
    Log-Message "Installing..." -Level Info

    # 1. 设置持久化环境变量
    [Environment]::SetEnvironmentVariable($EnvVarName, $TargetHome, [EnvironmentVariableTarget]::User)

    # 2. 更新注册表中的 Path
    $Path = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
    Log-Message "Old User PATH (Registry): $Path" -Level Info
    
    $PathEntries = $Path -split ";"
    $HomeEntry = "%$EnvVarName%"
    $ScriptsEntry = "%$EnvVarName%\scripts"

    $NewEntries = @()
    if ($PathEntries -notcontains $HomeEntry) { $NewEntries += $HomeEntry }
    if ($PathEntries -notcontains $ScriptsEntry) { $NewEntries += $ScriptsEntry }

    if ($NewEntries.Count -gt 0) {
        $NewPath = (($PathEntries | Where-Object { $_ -ne "" }) + $NewEntries) -join ";"
        Log-Message "Updating User PATH (Registry) to: $NewPath" -Level Info
        [Environment]::SetEnvironmentVariable("Path", $NewPath, [EnvironmentVariableTarget]::User)
    }

    # 3. 同步到当前会话
    $env:pw2401_home = $TargetHome
    $env:Path = "$TargetHome;$(Join-Path $TargetHome 'scripts');$env:Path"

    Log-Message "Installation complete. Registry updated." -Level Success
}

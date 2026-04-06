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
    $PathEntries = $Path -split ";" | Where-Object { 
        $_ -ne "%$EnvVarName%" -and $_ -ne $CurrentHome
    }
    $NewPath = @($PathEntries | Where-Object { $_ -ne "" }) -join ";"
    
    if ($Path -ne $NewPath) {
        Log-Message "Registry PATH Update: Backing up old path to pw2401_old_path" -Level Info
        Log-Message "Old PATH: $Path" -Level Info
        Log-Message "New PATH: $NewPath" -Level Success
        [Environment]::SetEnvironmentVariable("pw2401_old_path", $Path, [EnvironmentVariableTarget]::User)
        [Environment]::SetEnvironmentVariable("Path", $NewPath, [EnvironmentVariableTarget]::User)
    }

    # 2. 从注册表中彻底删除环境变量
    [Environment]::SetEnvironmentVariable($EnvVarName, [NullString]::Value, [EnvironmentVariableTarget]::User) 
    

    # 3. 清理当前会话 (Session) 中的变量，使其立即“消失”
    if (Test-Path "Env:\$EnvVarName") {
        Remove-Item "Env:\$EnvVarName"
    }
    
    # 4. (可选) 同步清理当前会话 de $env:Path，避免残留
    $env:Path = @($env:Path -split ";" | Where-Object { 
        $_ -ne $CurrentHome
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
    
    $PathEntries = $Path -split ";"
    $HomeEntry = "%$EnvVarName%"

    $NewEntries = @()
    if ($PathEntries -notcontains $HomeEntry) { $NewEntries += $HomeEntry }

    if ($NewEntries.Count -gt 0) {
        $NewPath = (@($PathEntries | Where-Object { $_ -ne "" }) + $NewEntries) -join ";"
        Log-Message "Registry PATH Update: Backing up old path to pw2401_old_path" -Level Info
        Log-Message "Old PATH: $Path" -Level Info
        Log-Message "New PATH: $NewPath" -Level Success
        [Environment]::SetEnvironmentVariable("pw2401_old_path", $Path, [EnvironmentVariableTarget]::User)
        [Environment]::SetEnvironmentVariable("Path", $NewPath, [EnvironmentVariableTarget]::User)
    }

    # 3. 同步到当前会话
    $env:pw2401_home = $TargetHome
    $env:Path = "$TargetHome;$env:Path"

    Log-Message "Installation complete. Registry updated." -Level Success
}

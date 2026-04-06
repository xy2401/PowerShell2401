<#
.SYNOPSIS
    重命名工具：支持定长补零对齐和智能去除公共前后缀。

.DESCRIPTION
    1. Pad (补零): 将文件名中的数字部分补齐到相同长度，方便排序。
    2. Trim (智能去缀): 自动识别所有选中文件的最大公共前缀和后缀并将其移除。
       目标是将 "(1).jpg", "(2).jpg" 重命名为 "1.jpg", "2.jpg"。

.PARAMETER Action
    执行的动作："pad" (补零), "trim" (智能去缀，默认), "rename" (按序重命名 1~n)。

.PARAMETER Path
    目标目录，默认为当前目录。

.PARAMETER Depth
    处理路径的深度。默认 0 即仅当前目录，1 表示包含所有一级子目录，以此类推。

.PARAMETER Recurse
    是否递归处理所有子目录。如果开启，将忽略 Depth 参数。

.PARAMETER Sort
    排序方式（仅用于 rename 动作）："name" (默认), "size" (按大小), "time" (按修改时间)。
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet("pad", "trim", "rename", "h", "help")]
    [string]$Action = "trim",
  
    [Parameter(HelpMessage = "处理路径的深度。默认 0 即仅当前目录，1 表示包含所有一级子目录，以此类推。")]
    [int]$Depth = 1,

    [Parameter(HelpMessage = "是否递归处理所有子目录。")]
    [switch]$Recurse,

    [Parameter(HelpMessage = "重命名时的排序方式。")]
    [ValidateSet("name", "size", "time")]
    [string]$Sort = "name"
)

$runtime = $global:GlobalConfig.runtime
$Path = $runtime.WorkDir
 

# --- 辅助工具函数 ---

function Get-CommonPrefix {
    param ([string[]]$Strings)
    if ($Strings.Count -le 1) { return if ($Strings.Count -eq 1) { $Strings[0] } else { "" } }
    $prefix = $Strings[0]
    foreach ($s in $Strings) {
        while ($prefix -and $s.IndexOf($prefix) -ne 0) {
            $prefix = $prefix.Substring(0, $prefix.Length - 1)
        }
    }
    return $prefix
}

function Get-CommonSuffix {
    param ([string[]]$Strings)
    if ($Strings.Count -le 1) { return "" }
    $reversed = $Strings | ForEach-Object { 
        $chars = $_.ToCharArray(); [Array]::Reverse($chars); -join $chars 
    }
    $lcp = Get-CommonPrefix -Strings $reversed
    $chars = $lcp.ToCharArray()
    [Array]::Reverse($chars)
    return (-join $chars)
}

# --- 核心功能函数 ---

function Invoke-PadZero {
    param ([string]$DirectoryPath)
    if ([string]::IsNullOrWhiteSpace($DirectoryPath)) { return }
    
    $files = Get-ChildItem -LiteralPath $DirectoryPath -File | Where-Object { $_.BaseName -match '\d+' }
    if (-not $files) { return }

    Log-Message ">>> 正在补零对齐: $DirectoryPath" -Level Info

    $maxNumLen = 0
    foreach ($f in $files) {
        if ($f.BaseName -match '(\d+)') {
            if ($matches[1].Length -gt $maxNumLen) { $maxNumLen = $matches[1].Length }
        }
    }

    foreach ($f in $files) {
        # 仅对不含扩展名的 BaseName 进行正则数字捕获与补零，防止误伤后缀名（如 .mp4 变成 .mp0004）
        $newBaseName = [regex]::Replace($f.BaseName, '(\d+)', {
                param($m) $m.Value.PadLeft($maxNumLen, '0')
            })
        
        # 补回原本原汁原味的后缀名
        $newName = $newBaseName + $f.Extension
        
        if ($newName -ne $f.Name) {
            Log-Message "Padding: $($f.Name) -> $newName" -Level Success
            Rename-Item -LiteralPath $f.FullName -NewName $newName -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-SmartTrim {
    param ([string]$DirectoryPath)
    if ([string]::IsNullOrWhiteSpace($DirectoryPath)) { return }

    Log-Message ">>> 正在智能去缀: $DirectoryPath" -Level Info

    # 1. 先补零
    Invoke-PadZero -DirectoryPath $DirectoryPath

    # 2. 获取列表
    $files = Get-ChildItem -LiteralPath $DirectoryPath -File
    $baseNames = $files | ForEach-Object { $_.BaseName }
    if ($baseNames.Count -le 1) { 
        Log-Message "文件数量不足，跳过提取。" -Level Info
        return 
    }

    # 3. 计算公共部分
    $prefix = Get-CommonPrefix -Strings $baseNames
    $suffix = Get-CommonSuffix -Strings $baseNames

    if (-not $prefix -and -not $suffix) {
        Log-Message "未发现公共前缀或后缀。" -Level Info
        return
    }

    Log-Message "识别到公共前缀: '$prefix', 公共后缀: '$suffix'" -Level Success

    # 4. 执行修剪
    foreach ($f in $files) {
        $name = $f.BaseName
        $ext = $f.Extension
        
        if ($prefix) { $name = $name.Substring($prefix.Length) }
        if ($suffix) { $name = $name.Substring(0, $name.Length - $suffix.Length) }

        if ([string]::IsNullOrWhiteSpace($name)) { $name = $f.BaseName }

        $newName = $name + $ext
        if ($newName -ne $f.Name) {
            $targetPath = Join-Path $f.DirectoryName $newName
            if (Test-Path -LiteralPath $targetPath) {
                Log-Message "冲突: $newName 已存在，跳过 $($f.Name)" -Level Warning
            }
            else {
                Log-Message "Trimming: $($f.Name) -> $newName" -Level Success
                Rename-Item -LiteralPath $f.FullName -NewName $newName -ErrorAction SilentlyContinue
            }
        }
    }
}

function Invoke-SequentialRename {
    param (
        [string]$DirectoryPath,
        [string]$SortType
    )
    if ([string]::IsNullOrWhiteSpace($DirectoryPath)) { return }

    Log-Message ">>> 正在按序重命名 (排序: $SortType): $DirectoryPath" -Level Info

    $files = Get-ChildItem -LiteralPath $DirectoryPath -File
    if (-not $files) { return }

    # 排序
    switch ($SortType) {
        "size" { $sortedFiles = $files | Sort-Object Length }
        "time" { $sortedFiles = $files | Sort-Object LastWriteTime }
        default { $sortedFiles = $files | Sort-Object Name }
    }

    # 第一步：重命名为临时名称，避免冲突
    $tempNames = @()
    $guid = [Guid]::NewGuid().ToString("N").Substring(0, 8)
    for ($i = 0; $i -lt $sortedFiles.Count; $i++) {
        $f = $sortedFiles[$i]
        $tempName = "_rename_tmp_$($guid)_$($i)$($f.Extension)"
        $tempPath = Join-Path $DirectoryPath $tempName
        Rename-Item -LiteralPath $f.FullName -NewName $tempName -Force
        $tempNames += $tempPath
    }

    # 第二步：重命名为 1, 2, 3...
    for ($i = 0; $i -lt $tempNames.Count; $i++) {
        $oldPath = $tempNames[$i]
        $ext = [System.IO.Path]::GetExtension($oldPath)
        $newName = "$($i + 1)$ext"
        
        Log-Message "Renaming [$SortType]: $($sortedFiles[$i].Name) -> $newName" -Level Success
        Rename-Item -LiteralPath $oldPath -NewName $newName -Force
    }
}

# --- 执行主流程 ---

# 1. 识别并获取目录列表
# 检查 $Path 变量。如果用户通过命令行 -Path 传递了值，它在这里就是有效的。
if (-not (Test-Path -LiteralPath $Path)) {
    Log-Message "路径不存在: $Path" -Level Error
    return
}

$baseDir = (Get-Item -LiteralPath $Path).FullName

if ($Recurse) {
    Log-Message "模式: 递归处理所有子目录" -Level Info
    $dirList = @($baseDir)
    $dirList += Get-ChildItem -LiteralPath $baseDir -Directory -Recurse | Select-Object -ExpandProperty FullName
}
else {
    Log-Message "模式: 精确保打击深度为 $Depth 的目录" -Level Info
    
    # 严格锁定处理只在指定的精确深度级产生 (复用 dir 核心套件的无交集遍历法)
    $targetDirs = Get-Directory-Depth -Path $baseDir -Depth $Depth
    $dirList = $targetDirs | Select-Object -ExpandProperty FullName
}

$uniqueDirs = $dirList | Select-Object -Unique
Log-Message "共发现 $($uniqueDirs.Count) 个目录待处理。" -Level Info

# 2. 遍历执行
foreach ($dir in $uniqueDirs) {
    switch ($Action) {
        "pad" { Invoke-PadZero -DirectoryPath $dir }
        "trim" { Invoke-SmartTrim -DirectoryPath $dir }
        "rename" { Invoke-SequentialRename -DirectoryPath $dir -SortType $Sort }
        "help" { Get-Help $PSCommandPath; return }
        "h" { Get-Help $PSCommandPath; return }
        default {
            Log-Message "未识别的动作: $Action。" -Level Warning
            Get-Help $PSCommandPath
            return
        }
    }
}

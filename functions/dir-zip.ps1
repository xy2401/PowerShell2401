[CmdletBinding(PositionalBinding = $false)]
param(
 
    [Parameter(HelpMessage = "处理路径的深度。默认 1 即仅当前目录的一级子目录，2 表示二级子目录，以此类推。")]
    [int]$Depth = 1,

    [Parameter(HelpMessage = "压缩包内是否包含顶级父目录。")]
    [switch]$IncludeBaseFolder,

    [Parameter(HelpMessage = "生成的压缩包的后缀名。默认为 .zip，也可以是 .cbz 等。")]
    [string]$Extension = ".zip"
)
$runtime = $global:GlobalConfig.runtime
$Path = $runtime.WorkDir
 
# 确保扩展名有 . 前缀
if (-not $Extension.StartsWith('.')) {
    $Extension = '.' + $Extension
}

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Host "[Error] 找不到目标目录: $Path" -ForegroundColor Red
    return
}

$suffix = $Extension
Update-Target -suffix $suffix
$runtime = $global:GlobalConfig.runtime

if (-not (Test-Path -LiteralPath $runtime.TargetDir)) {
    New-Item -ItemType Directory -Path $runtime.TargetDir | Out-Null
}

$sourceDir = (Get-Item -LiteralPath $Path).FullName

# 严格锁定处理只在指定的精确深度级产生 (杜绝交叉返回父子包含路径)
$targetDirs = Get-Directory-Depth -Path $Path -Depth $Depth

Write-Host "=> [Dir-Zip] 开始处理压缩任务，共选中 $($targetDirs.Count) 个目录" -ForegroundColor Cyan

foreach ($dir in $targetDirs) {
    $dirFullName = $dir.FullName
    $dirName = $dir.Name
    
    $zipFileName = $dirName + $Extension
    
    # 保持原有的相对目录结构放入 TargetDir 中
    $relativePath = ""
    if ($dir.Parent.FullName.Length -ge $sourceDir.Length) {
        $relativePath = $dir.Parent.FullName.Substring($sourceDir.Length).TrimStart("\")
    }
    $targetParentDir = Join-Path -Path $runtime.TargetDir -ChildPath $relativePath
    
    if (-not (Test-Path -LiteralPath $targetParentDir -PathType Container)) {
        New-Item -ItemType Directory -Path $targetParentDir -Force | Out-Null
    }

    $zipFilePath = Join-Path -Path $targetParentDir -ChildPath $zipFileName

    Write-Host "-----------------------------------------------"
    Write-Host "正在归档: $dirFullName"

    if (Test-Path -LiteralPath $zipFilePath) {
        Write-Host " [Warn] 目标压缩包已存在，跳过: $zipFileName" -ForegroundColor Yellow
        continue
    }

    try {
        # 使用 .NET 原生方法进行压缩，速度更快且灵活度高
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $dirFullName, 
            $zipFilePath, 
            [System.IO.Compression.CompressionLevel]::Optimal, 
            $IncludeBaseFolder.IsPresent
        )
        Write-Host " 状态: 成功压缩 => $zipFileName" -ForegroundColor Green
    }
    catch {
        Write-Host " [Error] 压缩期间发生错误: $_" -ForegroundColor Red
    }
}

Write-Host "=> [Dir-Zip] 处理完成！" -ForegroundColor Cyan

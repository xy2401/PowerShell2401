[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(HelpMessage = "处理路径的深度。默认 1 即仅当前目录的一级子目录，2 表示二级子目录，以此类推。")]
    [int]$Depth = 1,

    [Parameter(HelpMessage = "压缩包内是否包含顶级父目录。若为 false，则解压到以文件名命名的子目录中。")]
    [switch]$IncludeBaseFolder,

    [Parameter(HelpMessage = "支持的压缩包后缀名。")]
    [string[]]$Extensions = @(".zip", ".tar.gz", ".gz")
)

$runtime = $global:GlobalConfig.runtime
$Path = $runtime.WorkDir

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-LogMessage -NoPrefix "[Error] 找不到目标目录: $Path" -ForegroundColor Red
    return
}

# 规范化扩展名：确保都有 . 前缀，且按长度降序排列（处理 .tar.gz 优先于 .gz）
$sortedExtensions = $Extensions | ForEach-Object { if (-not $_.StartsWith('.')) { "." + $_ } else { $_ } } | Sort-Object -Property Length -Descending

# 更新目标目录
$suffix = ".unzip"
Update-Target -suffix $suffix
$runtime = $global:GlobalConfig.runtime

if (-not (Test-Path -LiteralPath $runtime.TargetDir)) {
    New-Item -ItemType Directory -Path $runtime.TargetDir -Force | Out-Null
}

$sourceDir = (Get-Item -LiteralPath $Path).FullName

# 获取目标扫描目录 (Depth 1 对应当前目录，即 Get-DirectoryDepth 0)
$scanDirs = Get-DirectoryDepth -Path $Path -Depth ($Depth - 1)

Write-LogMessage -NoPrefix "=> [Dir-Unzip] 开始扫描压缩包，深度: $Depth，扩展名: $($sortedExtensions -join ', ')" -ForegroundColor Cyan

$processedCount = 0

foreach ($dir in $scanDirs) {
    if ($null -eq $dir) { continue }
    $dirFullName = $dir.FullName
    
    # 在当前目录下查找符合扩展名的文件
    $files = Get-ChildItem -LiteralPath $dirFullName -File
    
    foreach ($file in $files) {
        $foundExt = $null
        foreach ($ext in $sortedExtensions) {
            if ($file.Name.EndsWith($ext, [System.StringComparison]::OrdinalIgnoreCase)) {
                $foundExt = $ext
                break
            }
        }

        if ($null -eq $foundExt) { continue }

        $fileFullName = $file.FullName
        $fileName = $file.Name
        
        # 计算相对于 SourceDir 的路径，以便在 TargetDir 中重建
        $relativePath = ""
        if ($file.DirectoryName.Length -ge $sourceDir.Length) {
            $relativePath = $file.DirectoryName.Substring($sourceDir.Length).TrimStart("\")
        }

        # 确定解压目标目录
        $baseName = $fileName.Substring(0, $fileName.Length - $foundExt.Length)
        $targetParentDir = Join-Path -Path $runtime.TargetDir -ChildPath $relativePath
        
        if (-not $IncludeBaseFolder) {
            # 如果不包含顶级目录，则解压到同名文件夹中
            $targetParentDir = Join-Path -Path $targetParentDir -ChildPath $baseName
        }

        if (-not (Test-Path -LiteralPath $targetParentDir -PathType Container)) {
            New-Item -ItemType Directory -Path $targetParentDir -Force | Out-Null
        }

        Write-LogMessage -NoPrefix "-----------------------------------------------"
        Write-LogMessage -NoPrefix "正在解压: $fileName"
        
        try {
            if ($foundExt -eq ".zip") {
                # 使用原生 Expand-Archive，稳定性好
                Expand-Archive -LiteralPath $fileFullName -DestinationPath $targetParentDir -Force
            }
            elseif ($foundExt -eq ".tar.gz") {
                # .tar.gz 必须使用 tar 工具
                tar -xf "$fileFullName" -C "$targetParentDir"
            }
            elseif ($foundExt -eq ".gz") {
                # 纯 .gz 文件（非 tarball）通常包含单个文件，tar 可能无法识别
                # 使用 .NET 原生 GZipStream 进行流式解压
                $destFileName = $baseName
                $destFilePath = Join-Path -Path $targetParentDir -ChildPath $destFileName
                
                $input = [System.IO.File]::OpenRead($fileFullName)
                
                # 读取 GZip 头部获取原始 MTIME (位置: 字节 4-7，小端序)
                $header = New-Object byte[] 10
                $input.Read($header, 0, 10) | Out-Null
                $mtime = [System.BitConverter]::ToUInt32($header, 4)
                $input.Position = 0 # 重置指针位置供 GZipStream 使用

                $output = [System.IO.File]::Create($destFilePath)
                $gzStream = [System.IO.Compression.GZipStream]::new($input, [System.IO.Compression.CompressionMode]::Decompress)
                try {
                    $gzStream.CopyTo($output)
                }
                finally {
                    $gzStream.Dispose()
                    $output.Dispose()
                    $input.Dispose()
                }

                # 恢复时间戳：优先使用 GZip 头部记录的原始时间，若为 0 则回退到压缩包文件时间
                if ($mtime -gt 0) {
                    $dt = [System.DateTimeOffset]::FromUnixTimeSeconds($mtime).LocalDateTime
                    (Get-Item -LiteralPath $destFilePath).LastWriteTime = $dt
                }
                else {
                    (Get-Item -LiteralPath $destFilePath).LastWriteTime = $file.LastWriteTime
                }
            }
            Write-LogMessage -NoPrefix " 状态: 成功解压 => $targetParentDir" -ForegroundColor Green
            $processedCount++
        }
        catch {
            Write-LogMessage -NoPrefix " [Error] 解压过程中发生错误: $_" -ForegroundColor Red
        }
    }
}

Write-LogMessage -NoPrefix "=> [Dir-Unzip] 处理完成！共成功处理 $processedCount 个压缩包。" -ForegroundColor Cyan

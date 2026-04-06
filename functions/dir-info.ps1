<#
.SYNOPSIS
    统计目录及子目录的文件信息，包括文件数量、文件夹数量、总大小以及基于后缀名的分类统计。

.DESCRIPTION
    该脚本扫描指定深度的目录，统计每个目录下的详细信息。
    分类依据包括：
    1. config.json 中定义的媒体类别 (image, video, audio, text, font 等)。
    2. 以 . 开头的隐藏文件。
    3. 无后缀名的文件。
    4. 不在 config.json 定义中的未知后缀名文件。
    统计时会排除所有隐藏文件夹 (如 .git, .vscode 等)。

.PARAMETER Depth
    扫描深度。0 表示仅统计当前目录，1 表示包含一级子目录，以此类推。默认值为 0。

.PARAMETER Csv
    是否导出 CSV 统计结果。启用后将在工作目录的父目录下生成以工作目录命名的 CSV 文件。

.EXAMPLE
    pw2401 dir-info -Depth 1 -Csv
#>

param(
    [int]$Depth = 0,
    [switch]$Csv,
    [switch]$ExtSummary
)

$runtime = $global:GlobalConfig.runtime
$workDir = $runtime.WorkDir

# 如果启用了 CSV 开关，则自动确定导出路径
$finalCsvPath = ""
if ($Csv) {
    $workDirName = Split-Path -Path $workDir -Leaf
    if ([string]::IsNullOrWhiteSpace($workDirName)) { $workDirName = "Root" }
    
    $parentPath = Split-Path -Path $workDir -Parent
    # 如果没有父目录（例如在根目录），则直接放在当前目录下
    if (-not $parentPath) { $parentPath = $workDir }
    
    $finalCsvPath = Join-Path -Path $parentPath -ChildPath "$workDirName.csv"
}

# 结果收集器（用于 CSV）
$allResults = [System.Collections.Generic.List[PSObject]]::new()
$globalExtStats = @{}

# 1. 获取目标文件夹列表
Log-Message "Scanning directories (Depth: $Depth, Exclude Hidden Folders)..." -Level Info

# 使用通用深度寻层逻辑获取目标目录
$targetDirs = Get-Directory-Depth -Path $workDir -Depth $Depth | 
Where-Object { $_.Name -notlike ".*" -and -not ($_.Attributes -match "Hidden") }

# 2. 从配置中获取动态类别
$categories = $global:GlobalConfig.extensions.PSObject.Properties.Name
Log-Message "Registered categories: $($categories -join ', ')" -Level Info

foreach ($dir in $targetDirs) {
    $dirPath = $dir.FullName
    
    # 计算相对路径，避免绝对路径过长
    $displayPath = $dirPath
    $currentDepth = 0
    if ($dirPath.StartsWith($workDir)) {
        $relativePath = $dirPath.Substring($workDir.Length).TrimStart("\")
        if ([string]::IsNullOrWhiteSpace($relativePath)) { 
            $displayPath = "." 
            $currentDepth = 0
        }
        else {
            $displayPath = $relativePath
            # 计算深度：通过计算路径中分隔符的数量
            $currentDepth = ($relativePath.Split("\[/]", [System.StringSplitOptions]::RemoveEmptyEntries)).Count
        }
    }

    Log-Message "`n--- Analyzing: $displayPath ---" -Level Info 
    Write-Host ("{0,-15} : {1}" -f "Directory Name", $dir.Name) -ForegroundColor Cyan
    Write-Host ("{0,-15} : {1}" -f "Relative Depth", $currentDepth) -ForegroundColor Cyan
    
    # 获取目录下所有非隐藏文件夹数量
    $allDirs = Get-ChildItem -LiteralPath $dirPath -Directory -Recurse | 
    Where-Object { 
        $relativePath = $_.FullName.Substring($dirPath.Length)
        $relativePath -notmatch '\\\.' 
    }
    $folderCount = if ($null -eq $allDirs) { 0 } else { $allDirs.Count }

    # 获取该目录下的直接子文件数量 (不包含子文件夹内文件)
    $directFiles = Get-ChildItem -LiteralPath $dirPath -File | 
    Where-Object { $_.Name -notlike ".*" -and -not ($_.Attributes -match "Hidden") }
    $subFilesTotal = if ($null -eq $directFiles) { 0 } else { $directFiles.Count }

    # 递归获取目录下所有文件，排除隐藏路径
    $allFiles = Get-ChildItem -LiteralPath $dirPath -File -Recurse | 
    Where-Object { 
        $relativePath = $_.FullName.Substring($dirPath.Length)
        $relativePath -notmatch '\\\.' 
    }

    if ($null -eq $allFiles -and $folderCount -eq 0) {
        Log-Message "No files or folders found in this directory." -Level Warning
        continue
    }

    # 初始化统计数据对象
    $stats = [Ordered]@{
        "TotalCount"  = 0
        "TotalSize"   = 0
        "Hidden"      = @{ Count = 0; Size = 0 }
        "NoExtension" = @{ Count = 0; Size = 0 }
        "Unknown"     = @{ Count = 0; Size = 0 }
    }
    
    foreach ($cat in $categories) {
        $stats[$cat] = @{ Count = 0; Size = 0 }
    }

    # 3. 遍历文件进行分类统计
    if ($null -ne $allFiles) {
        foreach ($file in $allFiles) {
            $size = $file.Length
            $stats.TotalCount++
            $stats.TotalSize += $size

            # A. 判断是否为 . 开头的隐藏文件
            if ($file.Name.StartsWith(".")) {
                $stats.Hidden.Count++
                $stats.Hidden.Size += $size
                continue
            }

            # B. 判断是否有后缀名
            $ext = $file.Extension.TrimStart('.')
            if ([string]::IsNullOrWhiteSpace($ext)) {
                $stats.NoExtension.Count++
                $stats.NoExtension.Size += $size
                continue
            }

            if ($ExtSummary) {
                # 统一转为小写以便统计
                $lowerExt = $ext.ToLower()
                if (-not $globalExtStats.ContainsKey($lowerExt)) {
                    $globalExtStats[$lowerExt] = 0
                }
                $globalExtStats[$lowerExt]++
            }

            # C. 使用 Get-FileType 进行分类
            $type = Get-FileType -FileName $file.Name
            if ($type -eq "unknown") {
                $stats.Unknown.Count++
                $stats.Unknown.Size += $size
            }
            else {
                $stats[$type].Count++
                $stats[$type].Size += $size
            }
        }
    }

    # 4. 输出统计结果
    Write-Host ("{0,-15} | {1,-10} | {2,-15}" -f "Category", "Count", "Size") -ForegroundColor Gray
    Write-Host ("-" * 45) -ForegroundColor Gray

    # 打印总计
    Write-Host ("{0,-15} | {1,-10} | {2,-15}" -f "Folders", $folderCount, "-") -ForegroundColor White
    Write-Host ("{0,-15} | {1,-10} | {2,-15}" -f "Direct Files", $subFilesTotal, "-") -ForegroundColor White
    Write-Host ("{0,-15} | {1,-10} | {2,-15}" -f "Files TOTAL", $stats.TotalCount, (Format-SizeText $stats.TotalSize)) -ForegroundColor White

    # 打印特殊分类
    $specialCats = @("Hidden", "NoExtension", "Unknown")
    foreach ($sc in $specialCats) {
        if ($stats[$sc].Count -gt 0) {
            Write-Host ("{0,-15} | {1,-10} | {2,-15}" -f $sc, $stats[$sc].Count, (Format-SizeText $stats[$sc].Size))
        }
    }

    # 打印动态类别
    foreach ($cat in $categories) {
        if ($stats[$cat].Count -gt 0) {
            Write-Host ("{0,-15} | {1,-10} | {2,-15}" -f $cat, $stats[$cat].Count, (Format-SizeText $stats[$cat].Size)) -ForegroundColor Green
        }
    }

    # 5. 如果需要导出 CSV，收集数据
    if ($Csv) {
        $row = [Ordered]@{
            "Name"              = $dir.Name
            "Depth"             = $currentDepth
            "Path"              = $displayPath
            "Folders"           = $folderCount
            "Sub_Files_Total"   = $subFilesTotal
            "Files_Total"       = $stats.TotalCount
            "Size_Total"        = $stats.TotalSize
            "Size_Total_Human"  = (Format-SizeText $stats.TotalSize)
            "Hidden_Cnt"        = $stats.Hidden.Count
            "Hidden_Size"       = $stats.Hidden.Size
            "Hidden_Size_Human" = (Format-SizeText $stats.Hidden.Size)
            "NoExt_Cnt"         = $stats.NoExtension.Count
            "NoExt_Size"        = $stats.NoExtension.Size
            "NoExt_Size_Human"  = (Format-SizeText $stats.NoExtension.Size)
            "Unknown_Cnt"       = $stats.Unknown.Count
            "Unknown_Size"      = $stats.Unknown.Size
            "Unknown_Size_Human"= (Format-SizeText $stats.Unknown.Size)
        }
        foreach ($cat in $categories) {
            $row["$($cat)_Cnt"]        = $stats[$cat].Count
            $row["$($cat)_Size"]       = $stats[$cat].Size
            $row["$($cat)_Size_Human"] = (Format-SizeText $stats[$cat].Size)
        }
        $allResults.Add([PSCustomObject]$row)
    }
}

# 导出 CSV
if ($Csv -and $allResults.Count -gt 0) {
    Log-Message "`nExporting results to: $finalCsvPath" -Level Info
    
    # --- 动态排序：将全为 0 的列移到最后 ---
    $sample = $allResults[0]
    $allProps = $sample.PSObject.Properties.Name
    
    # 基础列（始终在最前）
    $baseCols = @("Name", "Depth", "Path")
    # 待检查列
    $checkCols = $allProps | Where-Object { $baseCols -notcontains $_ }
    
    $nonZeroCols = @()
    $zeroCols = @()
    
    foreach ($col in $checkCols) {
        $isAllZero = $true
        foreach ($res in $allResults) {
            $val = $res.$col
            # 判断逻辑：数值为 0，或者格式化后为 "0 Bytes", "0.00 KB" 等 (Format-SizeText 的结果)
            if ($null -ne $val -and $val -ne "") {
                if ($val -is [ValueType]) {
                    if ($val -ne 0) { $isAllZero = $false; break }
                }
                elseif ($val -is [string]) {
                    # 匹配 "0", "0 Bytes", "0.00 KB", "0.00 MB", "0.00 GB"
                    if ($val -notmatch '^0(\.00)?\s*(Bytes|KB|MB|GB)?$') {
                        $isAllZero = $false;
                        break
                    }
                }
                else {
                    $isAllZero = $false; break
                }
            }
        }
        
        if ($isAllZero) {
            $zeroCols += $col
        } else {
            $nonZeroCols += $col
        }
    }
    
    $finalColOrder = $baseCols + $nonZeroCols + $zeroCols
    # ---------------------------------------

    # 自动创建父目录 (确保导出路径所在的目录存在)
    if (-not [string]::IsNullOrWhiteSpace($parentPath) -and -not (Test-Path -LiteralPath $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }
    
    $allResults | Select-Object -Property $finalColOrder | Export-Csv -LiteralPath $finalCsvPath -NoTypeInformation -Encoding utf8BOM
    Log-Message "Export Successful!" -Level Success
}

# 输出全局扩展名统计汇总
if ($ExtSummary -and $globalExtStats.Count -gt 0) {
    Log-Message "`n--- Global Extension Summary ---" -Level Info
    
    # 根据 config.json 构建后缀名到大类的映射表
    $extToCategory = @{}
    $extConfig = $global:GlobalConfig.extensions.PSObject.Properties
    foreach ($catProp in $extConfig) {
        $catName = $catProp.Name
        foreach ($e in $catProp.Value) {
            $extToCategory[$e.ToLower()] = $catName
        }
    }

    # 将统计结果按照大类进行分组
    $groupedStats = @{}
    foreach ($key in $globalExtStats.Keys) {
        $cat = $extToCategory[$key]
        if ([string]::IsNullOrWhiteSpace($cat)) {
            $cat = "Unknown"
        }
        
        if (-not $groupedStats.ContainsKey($cat)) {
            $groupedStats[$cat] = @{}
        }
        $groupedStats[$cat][$key] = $globalExtStats[$key]
    }

    # 分类打印输出
    $catOrder = $groupedStats.Keys | Sort-Object
    foreach ($cat in $catOrder) {
        Write-Host "[$cat]" -ForegroundColor Green
        $catExts = $groupedStats[$cat]
        
        # 将该大类下的扩展名按数量降序排列
        $sortedExts = $catExts.GetEnumerator() | Sort-Object Value -Descending
        foreach ($kv in $sortedExts) {
            Write-Host ("  .{0,-10} : {1}" -f $kv.Key, $kv.Value) -ForegroundColor Cyan
        }
    }
}

Log-Message "`nScan Complete." -Level Success

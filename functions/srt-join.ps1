[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$Path = ".",
    
    [Parameter(Mandatory = $true)]
    [string[]]$Lang,
    
    # 容错范围，单位秒，默认 1s 代表边界差在这个范围内也算同一个时间段
    [Parameter()]
    [double]$Tolerance = 0.1,
    
    # 最大可合并的段数，防止两个字幕链式重叠最终融合成超级长的一段
    [Parameter()]
    [int]$MaxMergeCount = 3,
    
    # 面积重合率（IoU），当两个字幕时间轴交并比大于此值时，直接判定为完美匹配的1:1隔离段
    [Parameter()]
    [double]$MatchRatio = 0.70,
    
    # 边界轻微重叠消除的最大退让比例（例如 0.1 代表最多牺牲自己 10% 的时长以防止错位。超出此阈值则说明是真实的场景重茬，保留）。
    [Parameter()]
    [double]$MaxYieldRatio = 0.10,
    
    # 开启后会在控制台打印极其详细的合并与计算切割日志
    [Parameter()]
    [switch]$DebugLog
)

$runtime = $global:GlobalConfig.runtime
if ($null -ne $runtime -and $Path -eq ".") {
    $Path = $runtime.WorkDir
}

$targetDir = $Path
if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $targetDir = Split-Path -Path $Path -Parent
}

$allFiles = Get-ChildItem -Path $targetDir -Filter "*.srt" -File

if ($allFiles.Count -eq 0) {
    Write-LogMessage -NoPrefix "在 $targetDir 没有找到任何 SRT 文件。" -ForegroundColor Yellow
    return
}

# 搜寻所有前缀 baseName (提取诸如 1.02-eng.srt 的前缀 1)
$baseNames = @()
foreach ($file in $allFiles) {
    foreach ($l in $Lang) {
        $escL = [regex]::Escape($l)
        $pattern = "^(.+?)[\.\-]$escL\.srt$"
        if ($file.Name -match $pattern) {
            $baseName = $matches[1]
            if ($baseNames -notcontains $baseName) {
                $baseNames += $baseName
            }
        }
    }
}

if ($baseNames.Count -eq 0) {
    Write-LogMessage -NoPrefix "未发现满足指定语言数组规则的字幕文件 ..." -ForegroundColor Yellow
    return
}

# 闭包辅助函数：解析 SRT 进对象
function Parse-Srt {
    param([string]$FilePath, [string]$LangTag)
    $lines = Get-Content $FilePath -Encoding UTF8
    $items = @()
    $currentItem = $null
    $state = "index" 
    
    foreach ($line in $lines) {
        # 清理 BOM 和空白
        $trimLine = $line.Trim() -replace '^\xEF\xBB\xBF', '' -replace '^\xFEFF', ''
        
        if ($state -eq "index") {
            if ($trimLine -match '^\d+$') {
                $currentItem = @{
                    Lang = $LangTag
                    Index = [int]$trimLine
                    TextLines = @()
                }
                $state = "time"
            }
        } elseif ($state -eq "time") {
            if ($trimLine -match '^(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})') {
                $currentItem.Start = [TimeSpan]::Parse($matches[1].Replace(',', '.'))
                $currentItem.End = [TimeSpan]::Parse($matches[2].Replace(',', '.'))
                $state = "text"
            } else {
                # 遇到异常时间线放弃当前块，回到找序号阶段
                $currentItem = $null
                $state = "index"
            }
        } elseif ($state -eq "text") {
            if ($trimLine -eq "") {
                if ($null -ne $currentItem -and $currentItem.TextLines.Count -gt 0) {
                    $items += [PSCustomObject]$currentItem
                }
                $currentItem = $null
                $state = "index"
            } else {
                $currentItem.TextLines += $trimLine
            }
        }
    }
    if ($currentItem -ne $null -and $currentItem.TextLines.Count -gt 0) {
        $items += [PSCustomObject]$currentItem
    }
    return $items
}

$toleranceSpan = [TimeSpan]::FromSeconds($Tolerance)

foreach ($baseName in $baseNames) {
    $langFiles = @{}
    $hasAll = $true
    foreach ($l in $Lang) {
        $path1 = Join-Path -Path $targetDir -ChildPath "$baseName.$l.srt"
        $path2 = Join-Path -Path $targetDir -ChildPath "$baseName-$l.srt"
        if (Test-Path -LiteralPath $path1) {
            $langFiles[$l] = $path1
        } elseif (Test-Path -LiteralPath $path2) {
            $langFiles[$l] = $path2
        } else {
            $hasAll = $false
            Write-LogMessage -NoPrefix "找不到组 $baseName 对应的语言字幕: $l" -ForegroundColor DarkGray
            break
        }
    }
    
    if (-not $hasAll) {
        continue
    }
    
    Write-LogMessage -NoPrefix "=========================================" -ForegroundColor Cyan
    Write-LogMessage -NoPrefix "合并字幕组: $baseName" -ForegroundColor Cyan
    
    $allSubtitles = @()
    foreach ($l in $Lang) {
        Write-LogMessage -NoPrefix "  -> 提取: $(Split-Path $langFiles[$l] -Leaf)"
        $allSubtitles += Parse-Srt -FilePath $langFiles[$l] -LangTag $l
    }
    
    Write-LogMessage -NoPrefix "  -> 总共有 $($allSubtitles.Count) 条字幕内容参与合并..."
    
    # 将所有的字幕段按时间先后排序
    $allSubtitles = $allSubtitles | Sort-Object Start, End
    
    # 步骤 1: 寻找精确匹配 (两边界差异均在容错范围内的 1:1 完全对应)
    $processed = [System.Collections.Generic.HashSet[PSCustomObject]]::new()
    $exactClusters = @()
    
    if ($Lang.Count -ge 2) {
        $firstLang = $Lang[0]
        $firstLangItems = $allSubtitles | Where-Object { $_.Lang -eq $firstLang }
        
        foreach ($item in $firstLangItems) {
            $clusterItems = @($item)
            
            for ($i = 1; $i -lt $Lang.Count; $i++) {
                $otherLang = $Lang[$i]
                $matched = $null
                # 遍历寻找完全匹配的另一个语言字幕 (且未被使用过的)
                foreach ($other in $allSubtitles) {
                    if ($other.Lang -eq $otherLang -and -not $processed.Contains($other)) {
                        # 计算面积交并比 (IoU)
                        $maxStart = [Math]::Max($item.Start.TotalSeconds, $other.Start.TotalSeconds)
                        $minEnd = [Math]::Min($item.End.TotalSeconds, $other.End.TotalSeconds)
                        $intersect = $minEnd - $maxStart
                        
                        $isMatch = $false
                        if ($intersect -gt 0) {
                            $minStart = [Math]::Min($item.Start.TotalSeconds, $other.Start.TotalSeconds)
                            $maxEnd = [Math]::Max($item.End.TotalSeconds, $other.End.TotalSeconds)
                            $union = $maxEnd - $minStart
                            $iou = $intersect / $union
                            
                            if ($iou -ge $MatchRatio) {
                                $isMatch = $true
                            }
                        }
                        
                        # 兜底：如果时间特别短没触及比例，但边界差完全在容错范围内，也算做匹配
                        if (-not $isMatch -and 
                            [Math]::Abs(($other.Start - $item.Start).TotalSeconds) -le $Tolerance -and 
                            [Math]::Abs(($other.End - $item.End).TotalSeconds) -le $Tolerance) {
                            $isMatch = $true
                        }

                        if ($isMatch) {
                            $matched = $other
                            if ($DebugLog) {
                                $perc = if ($intersect -gt 0 -and $union -gt 0) { [math]::Round($intersect / $union * 100, 1) } else { 0 }
                                Write-LogMessage -NoPrefix "[Step1: 1:1匹配] 第一轨($($item.Lang) 序号$($item.Index)) 及 匹配轨($($other.Lang) 序号$($other.Index)) (IoU面积比例: $perc%)" -ForegroundColor DarkCyan
                            }
                            break
                        }
                    }
                }
                if ($null -ne $matched) {
                    $clusterItems += $matched
                }
            }
            
            # 如果凑齐了所有语言均有完全对应，则锁定它们不再参与任何重叠吸附
            if ($clusterItems.Count -eq $Lang.Count) {
                foreach ($c in $clusterItems) { 
                    $processed.Add($c) | Out-Null
                }
                $minStart = $clusterItems[0].Start
                $maxEnd = $clusterItems[0].End
                foreach ($c in $clusterItems) {
                    if ($c.Start -lt $minStart) { $minStart = $c.Start }
                    if ($c.End -gt $maxEnd) { $maxEnd = $c.End }
                }
                
                $exactClusters += @{
                    Items = $clusterItems
                    Start = $minStart
                    End = $maxEnd
                    Counts = @{} 
                }
            }
        }
    }
    
    # 步骤 2: 提取剩下未能精确匹配的字幕进行交叉合并
    $remainingSubtitles = $allSubtitles | Where-Object { -not $processed.Contains($_) } | Sort-Object Start, End
    
    $chainedClusters = @()
    $currentCluster = $null
    
    foreach ($sub in $remainingSubtitles) {
        if ($null -eq $currentCluster) {
            $currentCluster = @{
                Items = @($sub)
                Start = $sub.Start
                End = $sub.End
                Counts = @{ ($sub.Lang) = 1 }
            }
        } else {
            $overlaps = $false
            foreach ($cItem in $currentCluster.Items) {
                if ($cItem.Lang -ne $sub.Lang) {
                    $maxStart = if ($cItem.Start -gt $sub.Start) { $cItem.Start } else { $sub.Start }
                    $minEnd = if ($cItem.End -lt $sub.End) { $cItem.End } else { $sub.End }
                    
                    $crossTime = ($minEnd - $maxStart).TotalSeconds
                    if ($crossTime -ge -($Tolerance)) {
                        $overlaps = $true
                        if ($DebugLog) {
                            $gapType = if ($crossTime -lt 0) { "微小相距: $([math]::Abs($crossTime))s" } else { "重叠: $($crossTime)s" }
                            Write-LogMessage -NoPrefix "[Step2: 链式缝合并发] -> 目标句($($sub.Lang) 序号$($sub.Index)) 与链内句($($cItem.Lang) 序号$($cItem.Index)) 产生 $gapType" -ForegroundColor DarkYellow
                        }
                        break
                    }
                }
            }
            
            $langCount = 0
            if ($currentCluster.Counts.ContainsKey($sub.Lang)) {
                $langCount = $currentCluster.Counts[$sub.Lang]
            }
            
            $canMerge = $overlaps -and ($langCount -lt $MaxMergeCount)
            
            if ($canMerge) {
                $currentCluster.Items += $sub
                if ($sub.Start -lt $currentCluster.Start) { $currentCluster.Start = $sub.Start }
                if ($sub.End -gt $currentCluster.End) { $currentCluster.End = $sub.End }
                $currentCluster.Counts[$sub.Lang] = $langCount + 1
            } else {
                $chainedClusters += $currentCluster
                $currentCluster = @{
                    Items = @($sub)
                    Start = $sub.Start
                    End = $sub.End
                    Counts = @{ ($sub.Lang) = 1 }
                }
            }
        }
    }
    
    if ($null -ne $currentCluster -and $currentCluster.Items.Count -gt 0) {
        $chainedClusters += $currentCluster
    }
    
    # 步骤 3: 汇总所有块，重新按时间排序
    $clusters = $exactClusters + $chainedClusters | Sort-Object Start
    
    Write-LogMessage -NoPrefix "  -> 合并完毕，共生成 $($exactClusters.Count) 个极准 1:1 结构，与 $($chainedClusters.Count) 个拼接混合群组 (容错: ${Tolerance}s, 拼接上限: $MaxMergeCount)"
    
    # 步骤 4: 后期微调，解除连续字幕段落群之间的轻微时间轴重叠
    for ($i = 0; $i -lt $clusters.Count - 1; $i++) {
        $prev = $clusters[$i]
        $next = $clusters[$i + 1]
        
        $overlapSecs = ($prev.End - $next.Start).TotalSeconds
        # 如果存在交叉
        if ($overlapSecs -gt 0) {
            $prevLen = ($prev.End - $prev.Start).TotalSeconds
            $nextLen = ($next.End - $next.Start).TotalSeconds
            
            # 计算双方各自的理论最大退让时间 (各 10%)
            $prevMaxYield = $prevLen * $MaxYieldRatio
            $nextMaxYield = $nextLen * $MaxYieldRatio
            
            # 如果重叠度在双方可最大退让长度之和的范围内，说明可以被完全抹平消除交集
            if ($overlapSecs -le ($prevMaxYield + $nextMaxYield)) {
                $totalLen = $prevLen + $nextLen
                $prevCutRatio = 0.5
                if ($totalLen -gt 0) {
                    $prevCutRatio = $prevLen / $totalLen
                }
                
                $prevCut = $overlapSecs * $prevCutRatio
                $nextCut = $overlapSecs * (1 - $prevCutRatio)
                
                # 收缩边界，并额外加 1 毫秒的安全间隙确保物理上绝对无交集
                $prev.End -= [TimeSpan]::FromSeconds($prevCut + 0.001)
                $next.Start += [TimeSpan]::FromSeconds($nextCut)
                if ($DebugLog) { Write-LogMessage -NoPrefix "[Step4: 边缘修剪] 群组 $i 与 群组 $($i+1) 轻微重叠 $([math]::Round($overlapSecs, 3))s -> 完美分离 (前级削去 $([math]::Round($prevCut, 3))s, 后级削去 $([math]::Round($nextCut, 3))s)" -ForegroundColor DarkMagenta }
            } else {
                # 如果重叠太大超出了极限阈值，说明是刻意的对话同框或长场景重叠。
                # 此时各自只进行其最大安全限制的退让，保留真实场景重叠状态。
                $prev.End -= [TimeSpan]::FromSeconds($prevMaxYield)
                $next.Start += [TimeSpan]::FromSeconds($nextMaxYield)
                if ($DebugLog) { Write-LogMessage -NoPrefix "[Step4: 边缘修剪] 群组 $i 与 群组 $($i+1) 大幅重叠 $([math]::Round($overlapSecs, 3))s -> 仅作极值退让 (前级极值 $([math]::Round($prevMaxYield, 3))s, 后级极值 $([math]::Round($nextMaxYield, 3))s)" -ForegroundColor DarkRed }
            }
            
            # 边界防御：最极端情况坚决不能把时间轴反扣了
            if ($prev.End -le $prev.Start) { $prev.End = $prev.Start + [TimeSpan]::FromMilliseconds(50) }
            if ($next.Start -ge $next.End) { $next.Start = $next.End - [TimeSpan]::FromMilliseconds(50) }
        }
    }

    # 格式化输出为新的 SRT 文本
    $outLines = New-Object System.Collections.Generic.List[string]
    $globalIndex = 1
    
    foreach ($cluster in $clusters) {
        $startStr = '{0:hh\:mm\:ss\,fff}' -f $cluster.Start
        $endStr = '{0:hh\:mm\:ss\,fff}' -f $cluster.End
        
        $outLines.Add($globalIndex.ToString())
        $outLines.Add("$startStr --> $endStr")
        
        # 按照入参语言数组顺序依次添加并显示字幕
        foreach ($l in $Lang) {
            $langItems = $cluster.Items | Where-Object { $_.Lang -eq $l } | Sort-Object Start
            if ($langItems.Count -gt 0) {
                foreach ($item in $langItems) {
                    foreach ($text in $item.TextLines) {
                        $outLines.Add($text)
                    }
                }
            }
        }
        
        $outLines.Add("")
        $globalIndex++
    }
    
    $langSuffix = $Lang -join '-'
    $outFileName = "$baseName.$langSuffix.srt"
    $outFilePath = Join-Path -Path $targetDir -ChildPath $outFileName
    [System.IO.File]::WriteAllLines($outFilePath, $outLines.ToArray(), [System.Text.Encoding]::UTF8)
    
    Write-LogMessage -NoPrefix "  -> 已保存至合并文件: $outFileName" -ForegroundColor Green
}

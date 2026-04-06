[CmdletBinding(PositionalBinding = $false)]
param(
 

    [Parameter(HelpMessage = "处理路径的深度。默认 1 即仅当前目录，1 表示包含所有一级子目录，以此类推。")]
    [int]$Depth = 1,

    [Parameter(HelpMessage = "是否自动替换剔除目录名末尾自带的一个 [...] 标签。默认开启以覆盖旧容量标签。设为 `$false` 避免误删你的普通末缀标签。")]
    [switch]$ReplaceLastTag ,

    [Parameter(HelpMessage = "各个指标的片段。包含对应占位符且值为0时，会自动被隐藏。")]
    [string[]]$Format = @("{P}P", "{V}V", "{Size}")
)

$runtime = $global:GlobalConfig.runtime
$Path = $runtime.WorkDir
 

# 动态确定一个日志文件名字
$logFileName = "dir-tag_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Init-Log $logFileName

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Log-Message -message "[Error] 找不到目标目录: $Path"
    return
}

# 严格锁定处理只在指定的精确深度级产生 (杜绝交叉返回父子包含路径)
$targetDirs = Get-Directory-Depth -Path $Path -Depth $Depth

Log-Message -message "=> [Dir-Tag] 开始处理目录标签任务，共选中 $($targetDirs.Count) 个目录"

foreach ($dir in $targetDirs) {
    $dirFullName = $dir.FullName
    $dirName = $dir.Name
    
    Log-Message -message "-----------------------------------------------"
    Log-Message -message "正在处理: $dirFullName"

    $imageCount = 0
    $videoCount = 0
    $totalSizeBytes = 0

    # 1. 获取该目录下的所有递归级文件
    $allFiles = Get-ChildItem -LiteralPath $dirFullName -File -Recurse 
    foreach ($file in $allFiles) {
        $totalSizeBytes += $file.Length
        # 实时调用高能效引擎进行极速鉴定后缀归属
        $type = Get-FileType -FileName $file.Name
        if ($type -eq "image") {
            $imageCount++
        }
        elseif ($type -eq "video") {
            $videoCount++
        }
    }

    # 2. 获取直接子文件夹数量 (仅统计一级)
    $subDirs = Get-ChildItem -LiteralPath $dirFullName -Directory
    $subDirCount = $subDirs.Count

    # 3. 计算大小并选择合适的刻度单位显示
    $sizeStr = Format-SizeText $totalSizeBytes

    # 4. 组装标签字符 (彻底放弃晦涩正则，利用数组分块的灵活性直接丢弃 0 值块)
    $tagParts = @()
    foreach ($item in $Format) {
        # 若任何一项的占位符它当前对应的数据恰好是 0，则一整个直接剔除跳过，不再显示
        if (($item -match '\{P\}' -and $imageCount -eq 0) -or 
            ($item -match '\{V\}' -and $videoCount -eq 0) -or 
            ($item -match '\{Size\}' -and $totalSizeBytes -eq 0) -or 
            ($item -match '\{D\}' -and $subDirCount -eq 0)) {
            continue
        }

        # 只要这块没被跳过，就替换入真实数值
        $part = $item.Replace("{P}", $imageCount.ToString()).Replace("{V}", $videoCount.ToString()).Replace("{Size}", $sizeStr).Replace("{D}", $subDirCount.ToString())
        if (-not [string]::IsNullOrWhiteSpace($part)) {
            $tagParts += $part
        }
    }

    $tagStr = ""
    if ($tagParts.Count -gt 0) {
        $tagStr = "[$( $tagParts -join ' ' )]"
    }

    # 5. 正则清理原有的末尾方括号标签
    $cleanName = $dirName
    if ($ReplaceLastTag) {
        # 仅剥离最后孤立存在的一个 [...] 标签区，强制去掉了原本的 While 循环
        # 这样就能严格保留名字靠前或者并列的其它标签 (例如 [美女] [10P]) 避免被全歼
        $cleanName = $cleanName -replace '\s*\[[^\]]+\]\s*$', ''
    }
    
    # 6. 生成新名字并检查是否需要重命名
    # 如果内部全是 0 使得新标签彻底为空，则不再拼接空尾巴
    if ([System.String]::IsNullOrWhiteSpace($tagStr)) {
        $newName = $cleanName.Trim()
    }
    else {
        $newName = -join ($cleanName, " ", $tagStr.Trim())
    }

    if ($dirName -ceq $newName) {
        Log-Message -message " 状态: 目录无数据变化，无需重命名 => ($newName)"
    }
    else {
        # 执行重命名操作
        try {
            Rename-Item -LiteralPath $dirFullName -NewName $newName -ErrorAction Stop
            Log-Message -message " 状态: 成功打上标签 => $newName"
        }
        catch {
            Log-Message -message " [Error] 此目录暂被占用或无权限重命名: $_"
        }
    }
}

Log-Message -message "=> [Dir-Tag] 处理完成！"
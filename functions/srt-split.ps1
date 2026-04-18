

$runtime = $global:GlobalConfig.runtime
$Path = $runtime.WorkDir

function Start-SrtSplitTask {
    param([string]$targetPath)
    
    # 强制设置输出编码为 UTF-8 以保证与 ffprobe 交互正常
    $oldOutputEncoding = $OutputEncoding
    $oldConsoleEncoding = [Console]::OutputEncoding
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    
    # 解析路径是文件还是文件夹
    $items = @()
    if (Test-Path -LiteralPath $targetPath) {
        $item = Get-Item -LiteralPath $targetPath
        if ($item -is [System.IO.FileInfo]) {
            $items = @($item)
        } else {
            # 如果是文件夹，则获取该文件夹下的视频文件
            $items = Get-ChildItem -LiteralPath $targetPath -File | Where-Object { (Get-FileType $_.Name) -eq 'video' }
        }
    } else {
        Write-LogMessage "找不到路径: $targetPath" -Level Error
        return
    }

    if ($items.Count -eq 0) {
        Write-LogMessage "未找到支持的视频文件。" -Level Warning
        return
    }

    foreach ($file in $items) {
        $videoPath = $file.FullName
        $baseName = $file.BaseName
        $dir = $file.DirectoryName
        
        Write-LogMessage -NoPrefix "========================================="
        Write-LogMessage "正在处理视频: $($file.Name)" -Level Info
        
        # 使用 ffprobe 获取字幕流信息
        # 优化项：指定 show_entries 仅获取需要的 index, codec_name 和 language 标签，避免巨大的 title 导致解析失败
        $ffprobeArgs = @(
            "-v", "error",
            "-print_format", "json",
            "-show_streams",
            "-select_streams", "s",
            "-show_entries", "stream=index,codec_name:stream_tags=language",
            $videoPath
        )
        
        $probeJson = & ffprobe @ffprobeArgs | Out-String
        
        if ([string]::IsNullOrWhiteSpace($probeJson)) {
            Write-LogMessage "  -> 未发现任何字幕流 (Probe 输出为空)" -Level Warning
            continue
        }
        
        $probeOutput = $null
        try {
            $probeOutput = $probeJson | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-LogMessage "  -> 字幕流信息解析失败: $($_.Exception.Message)" -Level Error
            Write-LogMessage "     [调试] 原始输出长度: $($probeJson.Length) 字符" -Level Error
            continue
        }
        
        if ($null -eq $probeOutput -or $null -eq $probeOutput.streams -or $probeOutput.streams.Count -eq 0) {
            Write-LogMessage "  -> 未发现字幕流" -Level Warning
            continue
        }
        
        $counter = 1
        foreach ($stream in $probeOutput.streams) {
            $absIndex = $stream.index
            $codec = $stream.codec_name
            
            # 获取语言，默认为 und
            $lang = "und"
            if ($null -ne $stream.tags -and $null -ne $stream.tags.language) {
                $lang = $stream.tags.language
            }
            
            # id 为顺序编号加语言名，如 01.eng 
            $id = "{0:D2}-$lang" -f $counter
            
            $outFileName = "$baseName.$id.srt"
            $outFilePath = Join-Path -Path $dir -ChildPath $outFileName
            
            Write-LogMessage "  [$counter] 提取字幕流 #$absIndex ($lang, $codec) -> $outFileName ..." -Level Info
            
            # 执行 ffmpeg 提取
            # -y 覆盖已存在的文件
            ffmpeg -y -v error -i "$videoPath" -map "0:$absIndex" "$outFilePath"
            
            # 如果源字幕是图片型的（如 pgs/vobsub/dvd_subtitle），直接转 srt 会失败并产生 0 字节文件
            if (Test-Path -LiteralPath "$outFilePath") {
                if ((Get-Item -LiteralPath "$outFilePath").Length -eq 0) {
                    Write-LogMessage "      [警告] 提取结果为空文件，可能是图片格式字幕(如PPS/PGS/VobSub)不支持直接转换为 SRT" -Level Warning
                    Remove-Item -LiteralPath "$outFilePath" -Force
                } else {
                    Write-LogMessage "      [成功] 完成" -Level Success
                }
            } else {
                Write-LogMessage "      [失败] 提取出错，可能是不支持的格式" -Level Error
            }
            
            $counter++
        }
    }
    # 恢复编码设置
    $OutputEncoding = $oldOutputEncoding
    [Console]::OutputEncoding = $oldConsoleEncoding
}

Start-SrtSplitTask -targetPath $Path

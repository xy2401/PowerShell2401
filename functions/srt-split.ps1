

$runtime = $global:GlobalConfig.runtime
$Path = $runtime.WorkDir

function Start-SrtSplitTask {
    param([string]$targetPath)
    
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
        $probeJson = ffprobe -v quiet -print_format json -show_streams -select_streams s "$videoPath"
        if ([string]::IsNullOrWhiteSpace($probeJson)) {
            Write-LogMessage "  -> 未发现任何字幕流" -Level Warning
            continue
        }
        
        $probeOutput = $probeJson | ConvertFrom-Json
        
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
}

Start-SrtSplitTask -targetPath $Path



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
            $videoExtensions = @(".mkv", ".mp4", ".avi", ".mov", ".wmv", ".flv", ".webm")
            $items = Get-ChildItem -LiteralPath $targetPath -File | Where-Object { $videoExtensions -contains $_.Extension.ToLower() }
        }
    } else {
        Write-Host "找不到路径: $targetPath" -ForegroundColor Red
        return
    }

    if ($items.Count -eq 0) {
        Write-Host "未找到支持的视频文件。" -ForegroundColor Yellow
        return
    }

    foreach ($file in $items) {
        $videoPath = $file.FullName
        $baseName = $file.BaseName
        $dir = $file.DirectoryName
        
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host "正在处理视频: $($file.Name)" -ForegroundColor Cyan
        
        # 使用 ffprobe 获取字幕流信息
        $probeJson = ffprobe -v quiet -print_format json -show_streams -select_streams s "$videoPath"
        if ([string]::IsNullOrWhiteSpace($probeJson)) {
            Write-Host "  -> 未发现任何字幕流" -ForegroundColor DarkGray
            continue
        }
        
        $probeOutput = $probeJson | ConvertFrom-Json
        
        if ($null -eq $probeOutput -or $null -eq $probeOutput.streams -or $probeOutput.streams.Count -eq 0) {
            Write-Host "  -> 未发现字幕流" -ForegroundColor DarkGray
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
            
            Write-Host "  [$counter] 提取字幕流 #$absIndex ($lang, $codec) -> $outFileName ..."
            
            # 执行 ffmpeg 提取
            # -y 覆盖已存在的文件
            ffmpeg -y -v error -i "$videoPath" -map "0:$absIndex" "$outFilePath"
            
            # 如果源字幕是图片型的（如 pgs/vobsub/dvd_subtitle），直接转 srt 会失败并产生 0 字节文件
            if (Test-Path -LiteralPath "$outFilePath") {
                if ((Get-Item -LiteralPath "$outFilePath").Length -eq 0) {
                    Write-Host "      [警告] 提取结果为空文件，可能是图片格式字幕(如PPS/PGS/VobSub)不支持直接转换为 SRT" -ForegroundColor Yellow
                    Remove-Item -LiteralPath "$outFilePath" -Force
                } else {
                    Write-Host "      [成功] 完成" -ForegroundColor Green
                }
            } else {
                Write-Host "      [失败] 提取出错，可能是不支持的格式" -ForegroundColor Red
            }
            
            $counter++
        }
    }
}

Start-SrtSplitTask -targetPath $Path

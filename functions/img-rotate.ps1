<#
.SYNOPSIS
    批量旋转当前目录下的图片。支持多种物理旋转与 EXIF 标签同步模式。

.DESCRIPTION
    该脚本提供以下两类核心操作：
    1. 同步操作：解决像素数据与 EXIF 旋转标签不一致的问题。
    2. 强制旋转：根据角度或宽高比需求，物理修改图片。

.PARAMETER SyncPixelsToExif
    【像素同步到标签】：读取 EXIF 旋转标签，物理旋转像素以匹配显示视角，完成后将标签重置。
    适用于：希望图片在所有不支持 EXIF 的软件中都能以“正确视角”显示。

.PARAMETER SyncExifToPixels
    【标签同步到像素】：不改变像素数据，强制将 EXIF 旋转标签重置为 1 (Normal)。
    适用于：像素本身已经是正的，但 EXIF 标签错误导致在某些查看器中显示歪了。

.PARAMETER Angle
    手动旋转的角度。可选值：90, 180, 270（顺时针）。

.PARAMETER ForceLandscape
    强制转换为横向：如果图片是纵向，则物理旋转 90 度为横向，并重置 EXIF 标签。

.PARAMETER ForcePortrait
    强制转换为纵向：如果图片是横向，则物理旋转 90 度为纵向，并重置 EXIF 标签。

.EXAMPLE
    pw2401 img-rotate -SyncPixelsToExif
    pw2401 img-rotate -SyncExifToPixels
    pw2401 img-rotate -Angle 90
    pw2401 img-rotate -ForceLandscape
#>

param(
    [switch]$SyncPixelsToExif,
    [switch]$SyncExifToPixels,
    [ValidateSet(90, 180, 270)]
    [int]$Angle = 0,
    [switch]$ForceLandscape,
    [switch]$ForcePortrait
)

$runtime = $global:GlobalConfig.runtime
$workDir = $runtime.WorkDir

# 检查依赖
Add-Type -AssemblyName System.Drawing

# 获取图片后缀列表
$imageExts = $global:GlobalConfig.extensions.image
if (-not $imageExts) {
    Write-LogMessage "未在 config.json 中找到图片后缀定义，退出。" -Level Error
    return
}

# 获取当前目录下所有图片文件
$files = Get-ChildItem -LiteralPath $workDir -File | Where-Object {
    $ext = $_.Extension.TrimStart('.').ToLower()
    $imageExts -contains $ext
}

if ($files.Count -eq 0) {
    Write-LogMessage "当前目录下未发现图片文件 (路径: $workDir)。" -Level Warning
    return
}

Write-LogMessage "准备处理 $($files.Count) 张图片..." -Level Info

foreach ($file in $files) {
    $filePath = $file.FullName
    $modified = $false
    $img = $null
    
    try {
        $stream = [System.IO.File]::OpenRead($filePath)
        $img = [System.Drawing.Image]::FromStream($stream)
        $stream.Close()
        $stream.Dispose()

        $rotateType = [System.Drawing.RotateFlipType]::RotateNoneFlipNone

        # 内部辅助函数：重置 EXIF 方向标签为 1 (Normal)
        $resetExif = {
            param($targetImg)
            if ($targetImg.PropertyIdList -contains 274) {
                $prop = $targetImg.GetPropertyItem(274)
                $prop.Value = [BitConverter]::GetBytes([int16]1)
                $targetImg.SetPropertyItem($prop)
            }
        }

        # 1. 物理旋转同步模式
        if ($SyncPixelsToExif) {
            if ($img.PropertyIdList -contains 274) {
                $propItem = $img.GetPropertyItem(274)
                $orientation = [BitConverter]::ToInt16($propItem.Value, 0)
                
                switch ($orientation) {
                    2 { $rotateType = [System.Drawing.RotateFlipType]::RotateNoneFlipX; $modified = $true }
                    3 { $rotateType = [System.Drawing.Rotate180FlipNone]; $modified = $true }
                    4 { $rotateType = [System.Drawing.Rotate180FlipX]; $modified = $true }
                    5 { $rotateType = [System.Drawing.Rotate270FlipX]; $modified = $true }
                    6 { $rotateType = [System.Drawing.Rotate90FlipNone]; $modified = $true }
                    7 { $rotateType = [System.Drawing.Rotate90FlipX]; $modified = $true }
                    8 { $rotateType = [System.Drawing.Rotate270FlipNone]; $modified = $true }
                }

                if ($modified) {
                    Write-LogMessage "图片 [$($file.Name)] 已物理旋转以匹配 EXIF 方向 ($orientation)。" -Level Info
                    $img.RotateFlip($rotateType)
                    &$resetExif $img
                }
            }
        }
        # 2. 仅重置标签同步模式
        elseif ($SyncExifToPixels) {
            if ($img.PropertyIdList -contains 274) {
                $orientation = [BitConverter]::ToInt16($img.GetPropertyItem(274).Value, 0)
                if ($orientation -ne 1) {
                    &$resetExif $img
                    $modified = $true
                    Write-LogMessage "图片 [$($file.Name)] 已重置 EXIF 标签以匹配物理视角 (原标签: $orientation)。" -Level Info
                }
            }
        }
        # 3. 手动旋转模式
        elseif ($Angle -ne 0) {
            $rotateType = switch ($Angle) {
                90  { [System.Drawing.RotateFlipType]::Rotate90FlipNone }
                180 { [System.Drawing.RotateFlipType]::Rotate180FlipNone }
                270 { [System.Drawing.RotateFlipType]::Rotate270FlipNone }
            }
            $img.RotateFlip($rotateType)
            &$resetExif $img
            $modified = $true
            Write-LogMessage "图片 [$($file.Name)] 手动旋转 $Angle 度并清零标签。" -Level Info
        }
        # 4. 强制宽高比模式
        elseif ($ForceLandscape -or $ForcePortrait) {
            $isLandscape = $img.Width -gt $img.Height
            if ($ForceLandscape -and -not $isLandscape) {
                $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone)
                &$resetExif $img
                $modified = $true
                Write-LogMessage "图片 [$($file.Name)] 强制转换为横向。" -Level Info
            }
            elseif ($ForcePortrait -and $isLandscape) {
                $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone)
                &$resetExif $img
                $modified = $true
                Write-LogMessage "图片 [$($file.Name)] 强制转换为纵向。" -Level Info
            }
        }

        # 保存修改
        if ($modified) {
            $tempPath = $filePath + ".tmp"
            $img.Save($tempPath, $img.RawFormat)
            $img.Dispose()
            $img = $null
            
            Remove-Item -LiteralPath $filePath -Force
            Move-Item -LiteralPath $tempPath -Destination $filePath -Force
        } else {
            $img.Dispose()
            $img = $null
        }

    } catch {
        Write-LogMessage "处理图片 [$($file.Name)] 时出错: $($_.Exception.Message)" -Level Error
        if ($null -ne $img) { $img.Dispose() }
    }
}

Write-LogMessage "任务完成。" -Level Success

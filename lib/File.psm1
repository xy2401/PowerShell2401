<#
.SYNOPSIS
    建立并缓存全局配置中的扩展名到媒体类别索引。

.DESCRIPTION
    缓存全局配置 $global:GlobalConfig.extensions 的扩展名索引，重复扩展名采用首个类别。
    配置对象替换后自动重建。原地修改 extensions 时使用 Refresh 显式刷新。
#>
function Get-FileTypeMap {
    param(
        [object]$Extensions = $global:GlobalConfig.extensions,
        [switch]$Refresh
    )

    if ($Refresh -or $null -eq $script:FileTypeMap -or
        -not [object]::ReferenceEquals($script:IndexedExtensions, $Extensions)) {
        $script:FileTypeMap = @{}
        foreach ($property in $Extensions.PSObject.Properties) {
            foreach ($extension in @($property.Value)) {
                $key = ([string]$extension).TrimStart('.').ToLowerInvariant()
                if ($key -and -not $script:FileTypeMap.ContainsKey($key)) {
                    $script:FileTypeMap[$key] = $property.Name
                }
            }
        }
        $script:IndexedExtensions = $Extensions
    }
    return $script:FileTypeMap
}

function Get-FileType {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FileName
    )

    # 提取拓展名，去掉开头的点，并统一转为小写以增强匹配健壮性
    $ext = [System.IO.Path]::GetExtension($FileName).TrimStart('.').ToLowerInvariant()
    
    if ([string]::IsNullOrWhiteSpace($ext)) {
        return "unknown"
    }

    $map = Get-FileTypeMap
    if ($map.ContainsKey($ext)) { return $map[$ext] }
    return 'unknown'
}

# 同目录暂存文件验证成功后再发布；替换失败时保留原目标。
function Complete-FileReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$TemporaryPath,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if ([IO.File]::Exists($Destination)) {
        [IO.File]::Replace($TemporaryPath, $Destination, [NullString]::Value)
    }
    else {
        [IO.File]::Move($TemporaryPath, $Destination)
    }
}

<#
.SYNOPSIS
    辅助函数：将字节数转换为友好格式 (如 1M, 1G)。
#>
function Format-SizeText {
    param ([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes Bytes"
}

<#
.SYNOPSIS
    读取图片的 EXIF 旋转方向，并返回修正后的真实宽高。

.DESCRIPTION
    读取 JPEG 图像中的 EXIF Orientation (274) 标签。
    当发生 90 度或 270 度旋转 (通常为 5,6,7,8) 时，会将原始的 Width 和 Height 进行调换。
#>
function Get-ImageTrueDimensions {
    param (
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][int]$RawWidth,
        [Parameter(Mandatory=$true)][int]$RawHeight
    )

    $Result = [PSCustomObject]@{
        Width  = $RawWidth
        Height = $RawHeight
        Exif   = "Normal"
    }

    $img = $null
    try {
        Add-Type -AssemblyName System.Drawing
        $img = [System.Drawing.Image]::FromFile($FilePath)
        if ($img.PropertyIdList -contains 274) {
            $orientation = [BitConverter]::ToInt16($img.GetPropertyItem(274).Value, 0)
            if ($orientation -in 5..8) {
                $Result.Exif   = "Rotated90/270 (EXIF $orientation)"
                $Result.Width  = $RawHeight
                $Result.Height = $RawWidth
            } else {
                $Result.Exif   = "Normal (EXIF $orientation)"
            }
        } else {
            $Result.Exif = "NoEXIF"
        }
    } catch {
        $Result.Exif = "Error"
    }
    finally {
        if ($null -ne $img) { $img.Dispose() }
    }

    return $Result
}

Export-ModuleMember -Function Get-FileTypeMap, Get-FileType, Complete-FileReplacement, Format-SizeText, Get-ImageTrueDimensions

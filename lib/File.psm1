<#
.SYNOPSIS
    根据文件名返回文件媒体类型 (基于全局配置 $global:GlobalConfig)

.DESCRIPTION
    动态遍历全局配置 $global:GlobalConfig.extensions 中的各类媒体后缀数组，
    匹配传入文件名的后缀并返回对应的类型名称（如 "image", "video", "audio", "text", "font" 等）。
    如果均未匹配或无后缀，则返回 "unknown"。
#>
function Get-FileType {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FileName
    )

    # 提取拓展名，去掉开头的点，并统一转为小写以增强匹配健壮性
    $ext = [System.IO.Path]::GetExtension($FileName).TrimStart('.').ToLower()
    
    if ([string]::IsNullOrWhiteSpace($ext)) {
        return "unknown"
    }

    # 从外部全局配置对象中安全获取拓展名映射
    $extensions = $global:GlobalConfig.extensions
    if ($null -eq $extensions) {
        return "unknown"
    }

    # 动态遍历配置中的所有媒体类别 (image, video, audio, text, font 等)
    foreach ($prop in $extensions.PSObject.Properties) {
        # 如果该属性的值是数组，且包含当前后缀，则返回该属性名作为类型
        if ($prop.Value -is [array] -and $prop.Value -contains $ext) {
            return $prop.Name
        }
    }

    return "unknown"
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

Export-ModuleMember -Function Get-FileType, Format-SizeText

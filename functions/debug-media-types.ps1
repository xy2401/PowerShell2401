<#
.SYNOPSIS
    更新媒体文件后缀名与 MIME 类型的映射关系。
    https://www.iana.org/assignments/media-types/media-types.xhtml
#>

function Update-MediaTypes {
    $mediaTypesDir = Join-Path $PSScriptRoot "..\tests\media-types"
    if (-not (Test-Path -LiteralPath $mediaTypesDir)) {
        New-Item -ItemType Directory -Path $mediaTypesDir -Force | Out-Null
    }

    # 已验证有效的 IANA CSV 链接
    $ianaFiles = @{
        "application" = "https://www.iana.org/assignments/media-types/application.csv"
        "audio"       = "https://www.iana.org/assignments/media-types/audio.csv"
        "font"        = "https://www.iana.org/assignments/media-types/font.csv"
        "haptics"     = "https://www.iana.org/assignments/media-types/haptics.csv"
        "image"       = "https://www.iana.org/assignments/media-types/image.csv"
        "message"     = "https://www.iana.org/assignments/media-types/message.csv"
        "model"       = "https://www.iana.org/assignments/media-types/model.csv"
        "multipart"   = "https://www.iana.org/assignments/media-types/multipart.csv"
        "text"        = "https://www.iana.org/assignments/media-types/text.csv"
        "video"       = "https://www.iana.org/assignments/media-types/video.csv"
    }

    foreach ($entry in $ianaFiles.GetEnumerator()) {
        $dest = Join-Path $mediaTypesDir "$($entry.Key).csv"
        Write-Host "Downloading $($entry.Value) to $dest..."
        try {
            Invoke-WebRequest -Uri $entry.Value -OutFile $dest -ErrorAction Stop
        } catch {
            Write-Warning "Failed to download $($entry.Key): $($_.Exception.Message)"
        }
    }

    # 修正后的 mime-db URL
    $mimeDbUrl = "https://raw.githubusercontent.com/jshttp/mime-db/master/db.json"
    $mimeDbPath = Join-Path $mediaTypesDir "db.json"
    Write-Host "Downloading $mimeDbUrl to $mimeDbPath..."
    try {
        Invoke-WebRequest -Uri $mimeDbUrl -OutFile $mimeDbPath -ErrorAction Stop
    } catch {
        Write-Warning "Failed to download db.json: $($_.Exception.Message)"
    }

    if (Test-Path -LiteralPath $mimeDbPath) {
        $mimeDb = Get-Content -LiteralPath $mimeDbPath -Raw | ConvertFrom-Json
        
        # 定义需要提取的类别及其 MIME 匹配模式
        $categoryMap = @(
            @{ Name = "image"; Pattern = "image/*" },
            @{ Name = "video"; Pattern = "video/*" },
            @{ Name = "audio"; Pattern = "audio/*" },
            @{ Name = "text";  Pattern = "text/*" },
            @{ Name = "font";  Pattern = "font/*" }
        )

        $configPath = Join-Path $PSScriptRoot "..\config.json"
        if (Test-Path -LiteralPath $configPath) {
            $configContent = Get-Content -LiteralPath $configPath -Raw
            try {
                $config = $configContent | ConvertFrom-Json
            } catch {
                # 简单修复末尾逗号
                $config = ($configContent -replace ',\s*}', '}') | ConvertFrom-Json
            }
            
            # 确保 extensions 节点存在且为对象
            if ($null -eq $config.extensions) {
                if ($config.PSObject.Properties["extensions"]) {
                    $config.extensions = [PSCustomObject]@{}
                } else {
                    $config | Add-Member -MemberType NoteProperty -Name "extensions" -Value ([PSCustomObject]@{})
                }
            }

            foreach ($item in $categoryMap) {
                $categoryName = $item.Name
                $pattern = $item.Pattern

                # 从 mime-db 中提取对应的后缀名
                # 注意：$_.Value.extensions 是数组，管道会自动展开
                $extensions = $mimeDb.PSObject.Properties | 
                    Where-Object { $_.Name -like $pattern } | 
                    ForEach-Object { $_.Value.extensions } | 
                    Where-Object { $_ -ne $null } | 
                    Select-Object -Unique | 
                    Sort-Object

                # 更新 config 对象中的 extensions
                if (-not ($config.extensions.PSObject.Properties[$categoryName])) {
                    $config.extensions | Add-Member -NotePropertyName $categoryName -NotePropertyValue $extensions
                } else {
                    $config.extensions.$categoryName = $extensions
                }

                Write-Host "Found $($extensions.Count) extensions for category: $categoryName"
            }

            # 保存更新后的 config.json
            $configJson = $config | ConvertTo-Json -Depth 10
            Set-Content -LiteralPath $configPath -Value $configJson
            Write-Host "`nSuccessfully updated config.json with new media extensions." -ForegroundColor Green
        } else {
            Write-Error "config.json not found at $configPath"
        }
    } else {
        Write-Error "Failed to download db.json"
    }
}

Update-MediaTypes

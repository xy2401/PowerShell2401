<!-- Generated from functions/img-rotate.ps1. Do not edit directly. -->

# img-rotate

批量旋转当前目录下的图片。支持多种物理旋转与 EXIF 标签同步模式。

## 用法

```powershell
pw2401 img-rotate [-SyncPixelsToExif <switch>] [-SyncExifToPixels <switch>] [-Angle <int>] [-ForceLandscape <switch>] [-ForcePortrait <switch>]
```

## 说明

该脚本提供以下两类核心操作：
1. 同步操作：解决像素数据与 EXIF 旋转标签不一致的问题。
2. 强制旋转：根据角度或宽高比需求，物理修改图片。
修改先保存到同目录临时文件，关闭图像资源后再替换原文件；失败时返回错误。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-SyncPixelsToExif` | `switch` | 否 | — | 【像素同步到标签】：读取 EXIF 旋转标签，物理旋转像素以匹配显示视角，完成后将标签重置。<br>适用于：希望图片在所有不支持 EXIF 的软件中都能以“正确视角”显示。 |
| `-SyncExifToPixels` | `switch` | 否 | — | 【标签同步到像素】：不改变像素数据，强制将 EXIF 旋转标签重置为 1 (Normal)。<br>适用于：像素本身已经是正的，但 EXIF 标签错误导致在某些查看器中显示歪了。 |
| `-Angle` | `int` | 否 | 0 | 手动旋转的角度。可选值：90, 180, 270（顺时针）。 |
| `-ForceLandscape` | `switch` | 否 | — | 强制转换为横向：如果图片是纵向，则物理旋转 90 度为横向，并重置 EXIF 标签。 |
| `-ForcePortrait` | `switch` | 否 | — | 强制转换为纵向：如果图片是横向，则物理旋转 90 度为纵向，并重置 EXIF 标签。 |

## 依赖

PowerShell

## 示例

### 示例 1：rotate-90

```powershell
pw2401 img-rotate -Angle 90
```

将当前目录中的受支持图片顺时针物理旋转 90 度。

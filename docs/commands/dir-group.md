<!-- Generated from functions/dir-group.ps1. Do not edit directly. -->

# dir-group

按媒体类型、视频时长或文件大小整理当前目录中的文件。

## 用法

```powershell
pw2401 dir-group [-Depth <int>] [-Groups <string[]>] [-DurationBins <int[]>] [-SizeBins <long[]>]
```

## 说明

在指定深度选择目录，将直接子文件分配到图片、视频、时长区间或大小区间文件夹中。
默认按图片和视频类型分组，移动操作发生在每个被选中的目录内部。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-Depth` | `int` | 否 | 1 | 要处理的精确目录深度。0 表示当前目录，1 表示直接子目录。 |
| `-Groups` | `string[]` | 否 | @("P", "V") | 分组维度。P 表示图片、V 表示视频、D 表示视频时长、S 表示文件大小。 |
| `-DurationBins` | `int[]` | 否 | @(60, 600, 3600) | 视频时长分组边界，单位为秒。 |
| `-SizeBins` | `long[]` | 否 | @(1MB, 10MB, 100MB, 1GB) | 文件大小分组边界，单位为字节。 |

## 依赖

PowerShell

## 示例

### 示例 1：group-media

```powershell
pw2401 dir-group -Depth 0 -Groups P,V
```

将当前目录的图片和视频分别移动到 P 与 V 子目录。

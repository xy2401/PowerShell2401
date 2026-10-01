<!-- Generated from functions/ff-vmaf.ps1. Do not edit directly. -->

# ff-vmaf

使用 FFmpeg libvmaf 比较源媒体与一个或多个编码目录。

## 用法

```powershell
pw2401 ff-vmaf -SourceDir <string> -EncodedDirs <string[]> [-Vertical <switch>]
```

## 说明

按相对路径和基础文件名匹配源文件与编码文件，计算 VMAF 分数并输出 CSV 汇总报告。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-SourceDir` | `string` | 是 | — | 参考源媒体目录。 |
| `-EncodedDirs` | `string[]` | 是 | — | 一个或多个待比较的编码目录。 |
| `-Vertical` | `switch` | 否 | — | 将 CSV 报告组织为纵向记录，而不是默认的横向透视格式。 |

## 依赖

ffmpeg, ffprobe, libvmaf

## 示例

### 示例 1：compare-directories

```powershell
pw2401 ff-vmaf -SourceDir source -EncodedDirs encoded
```

比较 source 与 encoded 目录中的同名媒体。

<!-- Generated from functions/ff-svt.ps1. Do not edit directly. -->

# ff-svt

使用 SVT-AV1 批量编码当前目录中的图片和视频。

## 用法

```powershell
pw2401 ff-svt [-Profile <string>] [-preset <string>] [-crf <string>]
```

## 说明

递归处理当前目录：图片输出为 AVIF，视频输出为 MP4，其他文件建立硬链接。
支持 fast、pro、ultra 和参数网格测试配置。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-Profile` | `string` | 否 | "pro" | 编码配置名称：fast、pro、ultra 或 for。 |
| `-preset` | `string` | 否 | "5" | SVT-AV1 编码速度预设，数值越小通常压缩效率越高、速度越慢。 |
| `-crf` | `string` | 否 | "32" | 恒定质量值，数值越低画质越高。 |

## 依赖

ffmpeg, ffprobe, libsvtav1

## 示例

### 示例 1：fast

```powershell
pw2401 ff-svt fast
```

使用快速 SVT-AV1 配置编码当前测试目录中的媒体。

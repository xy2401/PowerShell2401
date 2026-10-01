<!-- Generated from functions/ff-nv-av1.ps1. Do not edit directly. -->

# ff-nv-av1

使用 NVIDIA NVENC 将图片和视频批量编码为 AV1。

## 用法

```powershell
pw2401 ff-nv-av1 [-Profile <string>] [-preset <string>] [-cq <string>]
```

## 说明

递归处理当前目录：图片输出为 AVIF，视频输出为 MP4，其他文件建立硬链接。
支持 fast、pro、ultra 和参数网格测试配置。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-Profile` | `string` | 否 | "pro" | 编码配置名称：fast、pro、ultra 或 for。 |
| `-preset` | `string` | 否 | "p4" | NVENC 预设，取值通常为 p1 到 p7。 |
| `-cq` | `string` | 否 | "32" | NVENC 恒定质量值，数值越低画质越高。 |

## 依赖

ffmpeg, ffprobe, av1_nvenc

## 示例

### 示例 1：fast

```powershell
pw2401 ff-nv-av1 fast
```

使用快速 NVENC 配置编码当前测试目录中的媒体。

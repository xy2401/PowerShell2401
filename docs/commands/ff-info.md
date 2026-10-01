<!-- Generated from functions/ff-info.ps1. Do not edit directly. -->

# ff-info

为目录中的媒体文件导出 ffprobe JSON 信息。

## 用法

```powershell
pw2401 ff-info [-RemainingArguments <object>]
```

## 说明

递归扫描当前目录，将图片和视频的流及容器信息写入同级 .info 目录；其他文件使用硬链接保留目录镜像。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-RemainingArguments` | `object` | 否 | — | 保留的附加参数，目前不参与处理。 |

## 依赖

ffmpeg, ffprobe

## 示例

### 示例 1：inspect-media

```powershell
pw2401 ff-info
```

导出当前目录所有媒体文件的信息。

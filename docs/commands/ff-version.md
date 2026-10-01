<!-- Generated from functions/ff-version.ps1. Do not edit directly. -->

# ff-version

查看并记录 FFmpeg 及 SVT-AV1 的版本信息。

## 用法

```powershell
pw2401 ff-version
```

## 说明

该脚本会检测系统中配置的 FFmpeg 执行程序及其 SVT-AV1 编码器的详细版本。
通过执行一次极小的模拟编码任务来诱导 SVT 输出其内部版本号。
包含编码器列表以及 SVT/NVENC 的探测信息，并支持输出到独立日志。

## 依赖

ffmpeg, ffprobe

## 示例

### 示例 1：inspect-capabilities

```powershell
pw2401 ff-version
```

显示当前 FFmpeg 构建及可用 AV1 编码能力。

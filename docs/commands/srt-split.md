<!-- Generated from functions/srt-split.ps1. Do not edit directly. -->

# srt-split

从当前目录的视频中提取文本字幕流为 SRT 文件。

## 用法

```powershell
pw2401 srt-split
```

## 说明

使用 ffprobe 查找视频字幕流，并使用 FFmpeg 按语言和序号分别导出 SRT。
图片字幕无法直接转换时会删除生成的空文件并记录警告。

## 依赖

ffmpeg, ffprobe

## 示例

### 示例 1：extract-subtitles

```powershell
pw2401 srt-split
```

提取当前目录测试视频中的全部文本字幕流。

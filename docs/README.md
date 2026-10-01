<!-- Generated from functions/*.ps1. Do not edit directly. -->

# pw2401 命令文档

以下文档由各命令的 PowerShell 注释帮助自动生成。

| 命令 | 说明 | 依赖 |
|---|---|---|
| [dir-copy](commands/dir-copy.md) | 在同级目录下创建一个纯拷贝的镜像目录，支持多种条件过滤。 | PowerShell |
| [dir-group](commands/dir-group.md) | 按媒体类型、视频时长或文件大小整理当前目录中的文件。 | PowerShell |
| [dir-info](commands/dir-info.md) | 统计目录及子目录的文件信息，包括文件数量、文件夹数量、总大小以及基于后缀名的分类统计。 | PowerShell |
| [dir-tag](commands/dir-tag.md) | 根据目录中的媒体数量和总大小为目录名追加统计标签。 | PowerShell |
| [dir-trim](commands/dir-trim.md) | 重命名工具：支持定长补零对齐和智能去除公共前后缀。 | PowerShell |
| [dir-unzip](commands/dir-unzip.md) | 批量解压指定深度目录中的压缩文件。 | PowerShell |
| [dir-void](commands/dir-void.md) | 发现并清理空文件夹或仅含单个子目录的冗余文件夹。 | PowerShell |
| [dir-zip](commands/dir-zip.md) | 将指定深度的目录分别压缩为 ZIP 或 CBZ 文件。 | PowerShell |
| [ff-info](commands/ff-info.md) | 为目录中的媒体文件导出 ffprobe JSON 信息。 | ffmpeg, ffprobe |
| [ff-masonry](commands/ff-masonry.md) | 使用 FFmpeg 将多张图片拼接为瀑布流长图。 | ffmpeg, ffprobe |
| [ff-nv-av1](commands/ff-nv-av1.md) | 使用 NVIDIA NVENC 将图片和视频批量编码为 AV1。 | ffmpeg, ffprobe, av1_nvenc |
| [ff-svt](commands/ff-svt.md) | 使用 SVT-AV1 批量编码当前目录中的图片和视频。 | ffmpeg, ffprobe, libsvtav1 |
| [ff-version](commands/ff-version.md) | 查看并记录 FFmpeg 及 SVT-AV1 的版本信息。 | ffmpeg, ffprobe |
| [ff-vmaf](commands/ff-vmaf.md) | 使用 FFmpeg libvmaf 比较源媒体与一个或多个编码目录。 | ffmpeg, ffprobe, libvmaf |
| [hard-link](commands/hard-link.md) | 在同级目录下创建一个包含所有文件硬链接的镜像目录。 | PowerShell |
| [img-rotate](commands/img-rotate.md) | 批量旋转当前目录下的图片。支持多种物理旋转与 EXIF 标签同步模式。 | PowerShell |
| [srt-join](commands/srt-join.md) | 按时间轴合并多语言 SRT 字幕。 | PowerShell |
| [srt-join-ass](commands/srt-join-ass.md) | 将多语言 SRT 字幕合并为带样式的 ASS 字幕。 | PowerShell |
| [srt-split](commands/srt-split.md) | 从当前目录的视频中提取文本字幕流为 SRT 文件。 | ffmpeg, ffprobe |
| [sys-docs](commands/sys-docs.md) | 根据 functions 目录中的 PowerShell 注释帮助生成 Markdown 文档。 | 仅文档 |
| [sys-help](commands/sys-help.md) | 显示所有系统命令。 | PowerShell |
| [sys-install](commands/sys-install.md) | 安装或卸载当前用户的 pw2401 命令路径。 | 仅文档 |
| [sys-status](commands/sys-status.md) | 演示如何使用共享日志函数展示系统状态。 | PowerShell |
| [SystemInfo](commands/SystemInfo.md) | 显示 Windows 操作系统、处理器和内存信息。 | PowerShell |
| [test](commands/test.md) | 在隔离测试目录中执行命令文档里的 PowerShell 示例。 | 仅文档 |

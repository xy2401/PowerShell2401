<!-- Generated from functions/hard-link.ps1. Do not edit directly. -->

# hard-link

在同级目录下创建一个包含所有文件硬链接的镜像目录。

## 用法

```powershell
pw2401 hard-link
```

## 说明

该脚本会获取当前目录信息，并创建一个以 '.hardlink' 为后缀的目标目录。
它会保持原有的目录层级结构，并将所有文件通过 PowerShell 原生的 HardLink 方式镜像到目标位置。

## 依赖

PowerShell

## 示例

### 示例 1：mirror-links

```powershell
pw2401 hard-link
```

在当前目录同级创建 .hardlink 镜像。源目录和目标目录必须位于同一文件系统。

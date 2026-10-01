<!-- Generated from functions/sys-docs.ps1. Do not edit directly. -->

# sys-docs

根据 functions 目录中的 PowerShell 注释帮助生成 Markdown 文档。

## 用法

```powershell
pw2401 sys-docs
```

## 说明

校验所有正式命令的注释帮助，并在项目 docs 目录中生成命令索引和独立命令页面。
文档完全来源于脚本中的 .SYNOPSIS、.DESCRIPTION、.PARAMETER、.EXAMPLE 和 .NOTES。

## 示例

### 示例 1：generate-docs

```powershell
pw2401 docs
```

重新生成全部命令文档。

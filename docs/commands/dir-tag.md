<!-- Generated from functions/dir-tag.ps1. Do not edit directly. -->

# dir-tag

根据目录中的媒体数量和总大小为目录名追加统计标签。

## 用法

```powershell
pw2401 dir-tag [-Depth <int>] [-ReplaceLastTag <switch>] [-Format <string[]>]
```

## 说明

扫描指定深度的目录，统计图片、视频和文件总容量，并将格式化摘要追加到目录名末尾。
可以替换旧标签，也可以自定义标签片段。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-Depth` | `int` | 否 | 1 | 要标记的精确目录深度。1 表示当前目录的直接子目录。 |
| `-ReplaceLastTag` | `switch` | 否 | — | 在追加新统计信息前移除目录名末尾已有的方括号标签。 |
| `-Format` | `string[]` | 否 | @("{P}P", "{V}V", "{Size}") | 标签片段数组，支持 P、V 和 Size 占位符；值为零的片段会被隐藏。 |

## 依赖

PowerShell

## 示例

### 示例 1：replace-last-tag

```powershell
pw2401 dir-tag -Depth 1 -ReplaceLastTag
```

为当前目录的直接子目录更新媒体统计标签。

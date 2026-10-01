<!-- Generated from functions/dir-zip.ps1. Do not edit directly. -->

# dir-zip

将指定深度的目录分别压缩为 ZIP 或 CBZ 文件。

## 用法

```powershell
pw2401 dir-zip [-Depth <int>] [-IncludeBaseFolder <switch>] [-Extension <string>]
```

## 说明

选择精确深度的目录，为每个目录创建独立压缩包，并在当前目录同级的目标目录中保持相对结构。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-Depth` | `int` | 否 | 1 | 要压缩的精确目录深度。1 表示当前目录的直接子目录。 |
| `-IncludeBaseFolder` | `switch` | 否 | — | 在压缩包内保留被压缩目录本身作为顶级目录。 |
| `-Extension` | `string` | 否 | ".zip" | 输出压缩包扩展名，例如 .zip 或 .cbz。 |

## 依赖

PowerShell

## 示例

### 示例 1：zip-depth

```powershell
pw2401 dir-zip -Depth 1 -Extension .zip
```

将当前目录的直接子目录分别压缩为 ZIP 文件。

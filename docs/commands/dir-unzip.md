<!-- Generated from functions/dir-unzip.ps1. Do not edit directly. -->

# dir-unzip

批量解压指定深度目录中的压缩文件。

## 用法

```powershell
pw2401 dir-unzip [-Depth <int>] [-IncludeBaseFolder <switch>] [-Extensions <string[]>]
```

## 说明

扫描 ZIP、TAR.GZ 和 GZ 等压缩文件，在当前目录同级的 .unzip 目录中保持相对结构并解压内容。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-Depth` | `int` | 否 | 1 | 扫描压缩文件的目录深度。1 表示当前目录。 |
| `-IncludeBaseFolder` | `switch` | 否 | — | 解压时保留以压缩包文件名命名的顶级目录。 |
| `-Extensions` | `string[]` | 否 | @(".zip", ".tar.gz", ".gz") | 允许处理的压缩文件扩展名数组。 |

## 依赖

PowerShell

## 示例

### 示例 1：zip-depth

```powershell
pw2401 dir-unzip -Depth 1 -Extensions .zip
```

解压当前目录中的 ZIP 文件到同级 .unzip 目录。

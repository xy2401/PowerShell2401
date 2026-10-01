<!-- Generated from functions/dir-info.ps1. Do not edit directly. -->

# dir-info

统计目录及子目录的文件信息，包括文件数量、文件夹数量、总大小以及基于后缀名的分类统计。

## 用法

```powershell
pw2401 dir-info [-Depth <int>] [-Csv <switch>] [-ExtSummary <switch>]
```

## 说明

该脚本扫描指定深度的目录，统计每个目录下的详细信息。
分类依据包括：
1. config.json 中定义的媒体类别 (image, video, audio, text, font 等)。
2. 以 . 开头的隐藏文件。
3. 无后缀名的文件。
4. 不在 config.json 定义中的未知后缀名文件。
统计时会排除所有隐藏文件夹 (如 .git, .vscode 等)。
每个选中目录只遍历一次；扩展名重复时按 config.json 中首个类别归类。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-Depth` | `int` | 否 | 0 | 扫描深度。0 表示仅统计当前目录，1 表示包含一级子目录，以此类推。默认值为 0。 |
| `-Csv` | `switch` | 否 | — | 是否导出 CSV 统计结果。启用后将在工作目录的父目录下生成以工作目录命名的 CSV 文件。 |
| `-ExtSummary` | `switch` | 否 | — | 是否按扩展名进一步输出数量和容量汇总。 |

## 依赖

PowerShell

## 示例

### 示例 1：extension-summary

```powershell
pw2401 dir-info -Depth 1 -ExtSummary
```

统计一级子目录，并输出各文件扩展名汇总。

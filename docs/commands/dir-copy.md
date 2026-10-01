<!-- Generated from functions/dir-copy.ps1. Do not edit directly. -->

# dir-copy

在同级目录下创建一个纯拷贝的镜像目录，支持多种条件过滤。

## 用法

```powershell
pw2401 dir-copy [-Extension <string[]>] [-DeleteOriginal <switch>] [-ContainsText <string>] [-ContentRegex <string>] [-NameRegex <string>]
```

## 说明

该脚本会获取当前目录信息，并创建一个以 '.copy' 为后缀的目标目录。
支持按特定的文件后缀、文本内容、内容正则表达式或文件名正则表达式来筛选需要复制的文件。
先复制到目标目录的临时文件，校验大小并完成替换后才允许删除原文件。
复制或替换失败时保留源文件和已有目标文件，并以失败状态结束。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-Extension` | `string[]` | 否 | — | 指定要复制的文件名后缀数组（例如: html, css, .txt）。默认不区分大小写，且带不带前导点都可以。若未指定或为空，则复制所有后缀类型。 |
| `-DeleteOriginal` | `switch` | 否 | — | 一个开关参数。如果开启，复制成功后会将原始文件删除（类似于移动效果）。 |
| `-ContainsText` | `string` | 否 | — | 指定要包含的纯文本内容。只有文件内容中包含了该字符串，文件才会被拷贝。适用于过滤包含特定代码或日志的文件。 |
| `-ContentRegex` | `string` | 否 | — | 指定要匹配的正则表达式内容。只有文件内容匹配到了该正则表达式，文件才会被拷贝。 |
| `-NameRegex` | `string` | 否 | — | 指定要匹配的文件名正则表达式。只有文件名（或其部分）匹配该正则表达式，文件才会被拷贝。 |

## 依赖

PowerShell

## 示例

### 示例 1：extension-filter

```powershell
pw2401 dir-copy -Extension txt
```

将当前目录中的文本文件复制到同级的 .copy 目录，并保持原目录结构。

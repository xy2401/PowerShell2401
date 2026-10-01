<!-- Generated from functions/srt-join.ps1. Do not edit directly. -->

# srt-join

按时间轴合并多语言 SRT 字幕。

## 用法

```powershell
pw2401 srt-join -Lang <string[]> [-Tolerance <double>] [-MaxMergeCount <int>] [-MatchRatio <double>] [-MaxYieldRatio <double>]
```

## 说明

查找指定语言后缀的字幕文件，根据时间重合率和容差合并对应字幕段，并生成组合字幕文件。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-Lang` | `string[]` | 是 | — | 要合并的语言标签数组，例如 zh,en。 |
| `-Tolerance` | `double` | 否 | 0.1 | 时间边界匹配容差，单位为秒。 |
| `-MaxMergeCount` | `int` | 否 | 3 | 单个合并字幕段允许包含的最大原始段数。 |
| `-MatchRatio` | `double` | 否 | 0.70 | 判定两个时间段直接匹配所需的最小交并比。 |
| `-MaxYieldRatio` | `double` | 否 | 0.10 | 为消除轻微边界重叠允许缩短字幕段的最大比例。 |

## 依赖

PowerShell

## 示例

### 示例 1：bilingual

```powershell
pw2401 srt-join -Lang zh,en
```

合并当前目录中的 sample.zh.srt 和 sample.en.srt。

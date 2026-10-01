<!-- Generated from functions/srt-join-ass.ps1. Do not edit directly. -->

# srt-join-ass

将多语言 SRT 字幕合并为带样式的 ASS 字幕。

## 用法

```powershell
pw2401 srt-join-ass -Lang <string[]> [-OutputName <string>]
```

## 说明

读取指定语言标签的 SRT 文件，将不同语言映射到 ASS 样式并输出组合字幕。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-Lang` | `string[]` | 是 | — | 要合并的语言标签数组，例如 zh,en。 |
| `-OutputName` | `string` | 否 | — | 输出 ASS 文件名；省略时根据输入文件名称自动生成。 |

## 依赖

PowerShell

## 示例

### 示例 1：bilingual-ass

```powershell
pw2401 srt-join-ass -Lang zh,en -OutputName combined.ass
```

将当前目录中的中英文字幕合并为 combined.ass。

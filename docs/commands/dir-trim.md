<!-- Generated from functions/dir-trim.ps1. Do not edit directly. -->

# dir-trim

重命名工具：支持定长补零对齐和智能去除公共前后缀。

## 用法

```powershell
pw2401 dir-trim [-Action <string>] [-Depth <int>] [-Recurse <switch>] [-Sort <string>]
```

## 说明

1. Pad (补零): 将文件名中的数字部分补齐到相同长度，方便排序。
2. Trim (智能去缀): 自动识别所有选中文件的最大公共前缀和后缀并将其移除。
   目标是将 "(1).jpg", "(2).jpg" 重命名为 "1.jpg", "2.jpg"。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-Action` | `string` | 否 | "trim" | 执行的动作："pad" (补零), "trim" (智能去缀，默认), "rename" (按序重命名 1~n)。 |
| `-Depth` | `int` | 否 | 1 | 处理路径的深度。默认 0 即仅当前目录，1 表示包含所有一级子目录，以此类推。 |
| `-Recurse` | `switch` | 否 | — | 是否递归处理所有子目录。如果开启，将忽略 Depth 参数。 |
| `-Sort` | `string` | 否 | "name" | 排序方式（仅用于 rename 动作）："name" (默认), "size" (按大小), "time" (按修改时间)。 |

## 依赖

PowerShell

## 示例

### 示例 1：pad-numbers

```powershell
pw2401 dir-trim pad -Depth 0
```

将当前目录文件名中的数字补齐到统一宽度。

<!-- Generated from functions/test.ps1. Do not edit directly. -->

# test

在隔离测试目录中执行命令文档里的 PowerShell 示例。

## 用法

```powershell
pw2401 test [-External <switch>]
```

## 说明

默认执行只依赖 PowerShell 的示例。使用 External 开关后，同时执行 FFmpeg 等外部依赖示例。
每个示例通过同目录的同名 PSD1 文件声明独立测试数据和预期结果，实际命令来自注释帮助中的 ExampleId。
无论通过还是失败，输入、生成文件和进程输出都会保留在 target 中；Skip 不创建空 case。
标准输出保存为 stdout.txt；PowerShell 序列化流保存为 streams.clixml，其他原始流保存为 streams.txt。
同时运行文件安全、EXIF 方向和分类一致性回归测试；External 开关增加真实媒体探测回归测试。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-External` | `switch` | 否 | — | 同时运行依赖 FFmpeg、ffprobe、编码器或滤镜的外部测试。 |

## 示例

### 示例 1：powershell-only

```powershell
pw2401 test
```

执行全部纯 PowerShell 示例并生成 Markdown 与 JSON 报告。

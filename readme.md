# PowerShell 2401 (pw2401) 实用工具箱

[![Docs and tests](https://github.com/xy2401/PowerShell2401/actions/workflows/docs-and-tests.yml/badge.svg)](https://github.com/xy2401/PowerShell2401/actions/workflows/docs-and-tests.yml)

这是一个基于 PowerShell 的多功能、高性能脚手架与工具库。旨在通过统一、优雅的入口命令简化视频图像处理、文件收纳与分类管理。底层集成 FFmpeg 等行业标准工具，并使用高度优化的 PowerShell 逻辑提供顺畅的使用体验。

## 🚀 快速开始

### 1. 安装与配置
首先，将项目目录添加到系统的全局变量中，以便在任何地方调用。

1. 以管理员权限打开最新的 PowerShell 7 (`pwsh`)。
2. 进入项目根目录。
3. 执行安全的环境安装脚本（此脚本具备容错功能，不会损坏你现有的 Path 环境变量）：
   ```powershell
   pwsh ./pw2401.ps1 install
   ```
4. 安装完成后，**重启终端**，即可全局无缝使用 `pw2401` 命令。

### 2. 标准使用格式
整个系统统一了入口调用，具有透明参数转发和智能类型解析的特点，彻底打破了 PowerShell 复杂的参数输入门槛：
```powershell
pw2401 <功能名称> [功能相关参数...]
```
*如果不带参数直接执行 `pw2401`，将输出可用命令的快速列表。*

### 3. 命令文档与示例测试

完整命令文档由各脚本开头的 PowerShell 注释帮助自动生成，入口见 [docs/README.md](docs/README.md)。

```powershell
pw2401 docs           # 重新生成命令文档
pw2401 test           # 执行纯 PowerShell 示例
pw2401 test -External # 同时执行 FFmpeg 等外部依赖示例
```

测试数据和报告位于当前目录的 `target/pw2401-tests/`。所有已执行 case 无论通过还是失败都会保留，Skip 不创建空目录，原始 `tests/magika_basic` 素材不会被修改。

`pw2401 test` 同时运行 `tests/TestRegression.ps1` 中的回归测试，覆盖复制失败、文件占用、EXIF 方向 2–8、分类一致性和未知媒体时长，并自动运行 `tests/TestChromeLauncher.ps1` 验证 Chrome 实例启动器。Chrome 测试使用 `target/` 下的隔离目录和替代启动函数，不会打开浏览器或修改实际用户配置。文件安全测试分别验证默认 `Continue` 与严格 `Stop` 错误策略；结果保存在 `target/pw2401-tests/regressions/`。示例测试保持严格错误策略，PSD1 的 `Images` 与 `Media` 断言可检查实际宽高、EXIF 方向、媒体类型及最小时长。

每个 case 的标准输出保存在 `stdout.txt`；PowerShell 序列化信息流使用原生的 `streams.clixml` 后缀，非 CLIXML 原始流保存为 `streams.txt`。这些流文件不等同于测试错误，测试结论以报告中的状态和断言为准。

每个可测试命令由同目录的同名文件共同维护：`functions/<命令>.ps1` 保存实现、注释帮助和带稳定 `ExampleId` 的真实示例，`functions/<命令>.psd1` 声明 case 输入与预期输出。PSD1 由 PowerShell 原生读取，不包含可执行命令；测试引擎只提供复制文件、创建目录、创建文本文件和结果断言等通用能力。外部媒体测试使用仓库中的微型 `tests/fixtures/`，不会在配置文件里硬编码 FFmpeg 命令。

GitHub Actions 在 Windows hosted runner 上执行文档一致性、纯 PowerShell 示例和 FFmpeg 外部示例。外部 job 安装 `ffmpeg-full`；缺少 `libsvtav1`、`libvmaf`、`av1_nvenc` 或 NVIDIA 运行能力时，对应用例记为 Skip，不会使工作流失败。每次测试报告作为 artifact 保留 7 天。

### 4. 独立脚本

`functions/` 中的命令通过 `pw2401` 入口调用；`standalone/` 中的脚本有自己的执行入口，可以直接通过 `pwsh -File` 运行。

例如，从项目根目录运行 [standalone/ff_masonry.ps1](standalone/ff_masonry.ps1)：

```powershell
pwsh -NoProfile -File ./standalone/ff_masonry.ps1 -ColumnCount 3 -CanvasWidth 1920 -Gap 10
```

该脚本读取当前工作目录中的图片，需要 `ffmpeg` 和 `ffprobe` 在 PATH 中。处理其他目录时，先切换到素材目录，再用脚本的绝对路径运行。

#### Chrome 实例启动器

[standalone/chrome-profile.ps1](standalone/chrome-profile.ps1) 是面向 Windows、PowerShell 7 的单文件脚本，可以单独复制使用。首个参数是实例名，允许字母、数字、连字符和下划线，统一转为小写。每个实例具有独立的浏览器数据和可重复使用的启动配置。

将 `standalone` 目录加入 PATH 后，可以在 PowerShell 中直接运行 `chrome-profile.ps1 work` 或 `chrome-profile.ps1 work -Try`。入口使用 `chrome-profile` 名称，便于与 Chrome 浏览器命令区分。

从项目根目录执行：

```powershell
# 不带参数：显示简短用法及所有已保存 profile 的环境变量覆盖和完整启动命令
pwsh -NoProfile -File ./standalone/chrome-profile.ps1

# 创建或启动 work；自动复用已保存的参数、环境变量和程序路径
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work

# 保存或更新代理并启动；以后只输入 work 也会使用该代理
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work --proxy-server=http://127.0.0.1:7890

# 保存网址并启动；以后每次启动都会携带该网址
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work https://example.com

# 清空参数和网址并启动；也可以在后面提供替换后的新参数
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work -ClearArgs
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work -ClearArgs --incognito

# 保存环境变量、删除指定覆盖项或清空所有覆盖项，然后启动
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work -SetEnv 'NAME=value'
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work -RemoveEnv NAME
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work -ClearEnv

# 保存自定义 Chrome 路径；重置后恢复自动查找
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work -ExecutablePath 'D:\Apps\Chrome\chrome.exe'
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work -ResetExecutable

# 调试预览：先应用本次参数，再打印自定义环境变量设置和完整启动命令，不保存、不创建目录、不启动
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work -Try
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work -Try --proxy-server=http://127.0.0.1:8080 -SetEnv 'NAME=debug'
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 work -Try -ClearArgs --proxy-server=http://127.0.0.1:8080

# 显示完整说明和示例
pwsh -NoProfile -File ./standalone/chrome-profile.ps1 -Help
```

配置固定保存在 Windows 用户主目录的 `.pw2401/chrome.{Profile}/` 下，与运行脚本时的工作目录无关。实例 `work` 对应目录如下：

```text
~/.pw2401/chrome.work/
├── launch.json    # UTF-8 启动配置，可手工编辑
└── user-data/     # Chrome 用户数据目录
```

`launch.json` 示例：

```json
{
  "executablePath": null,
  "arguments": [
    "--proxy-server=http://127.0.0.1:7890",
    "https://example.com"
  ],
  "environment": {
    "NAME": "value"
  }
}
```

- Chrome 开关使用 `--名称=值` 或 `--名称`；含空格时引用整个参数，例如 `'--user-agent=Work Browser'`。同名开关以本次值覆盖，其他开关保留；网址和文件路径也会保存，相同条目去重。配置里的每项都是一个完整参数，不拆词、不执行其中的代码。
- `-ClearArgs` 只清空参数和网址，`-ClearEnv` 只清空环境变量覆盖，`-ResetExecutable` 只重置程序路径。组合操作先清除或重置，再删除指定环境变量覆盖，最后应用本次设置；这些操作都保留浏览器数据。
- `-SetEnv`、`-RemoveEnv` 可以重复提供；`-SetEnv` 按第一个 `=` 分隔名称和值。环境变量继承当前进程，再叠加实例的覆盖项，仅影响 Chrome 及其子进程。删除覆盖项后恢复继承父进程的值。
- 自定义程序路径保存为绝对路径；`executablePath` 为 `null` 时依次查找 PATH、Windows App Paths 注册项和常见安装位置。明确指定的路径失效时报告错误。
- `-Try` 用于调试，可以放在实例名之后的任意位置。先读取保存的配置，再应用本次所有配置选项和 Chrome 参数；本次同名开关和环境变量覆盖旧值，其他设置保留。输出先列出自定义环境变量覆盖的 PowerShell 设置语句，再列出 Chrome 程序的绝对路径和全部启动参数，长值不截断。继承而未覆盖的环境变量不展开打印。所有变更只在内存中生效，打印的语句不会执行，不保存、不启动，新实例也不会创建目录。
- 无参数运行时先显示几行简短用法和 `.pw2401/chrome.{Profile}` 目录模板，再按名称列出 `.pw2401/` 下的 `chrome.` 前缀目录对应的所有 profile，并逐个输出与 `<实例名> -Try` 相同的自定义环境变量设置和完整启动命令。仅有浏览器数据、缺少 `launch.json` 的 profile 按默认空配置预览。没有 profile 时显示提示，不创建目录；单个 profile 配置损坏或程序路径失效时显示原因，继续预览其他 profile。显式 `-Help` 显示完整说明和示例，不列出 profile。

例如，`-Try -SetEnv 'NAME=debug' --proxy-server=http://127.0.0.1:8080` 的调试输出会包含以下形式的语句（实际路径和参数根据实例计算）：

```powershell
$env:NAME = 'debug'
& 'C:\Program Files\Google\Chrome\Application\chrome.exe' '--user-data-dir=C:\Users\用户名\.pw2401\chrome.work\user-data' '--proxy-server=http://127.0.0.1:8080'
```

保存配置中的自定义环境变量也会列出；`-RemoveEnv` 或 `-ClearEnv` 删除的覆盖项不会再打印设置语句。Chrome 的代理仍通过 `--proxy-server` 等 Chrome 参数传入。

最终启动命令先设置脚本管理的 `--user-data-dir`，再追加保存的用户参数；禁止通过用户参数覆盖该目录。若同一实例已在运行，Chrome 可能复用现有进程；修改参数或环境变量后，应完全关闭该实例再启动。`-Try` 显示的是本次准备启动的配置。

---

## 🛠️ 核心功能模块全览与使用方式

### 🎬 视频与图像高端处理 (FFmpeg 生态)
本模块将冗长难懂的 FFmpeg 命令沉淀为开箱即用的现代化接口。

*   **`ff-masonry` (自动瀑布流拼接排版)**
    *   **描述**：扫描指定目录深度的图片，自动计算并生成专业级极高分辨率的纯净排版长图瀑布（含智能裁剪与文字水印嵌入）。
    *   **高光参数**：`-Depth`（递归层级）、`-ColumnCount`（列数）、`-UniformCrop`（强制等比统一尺寸）、`-CropSize`（裁剪基准）、`-DrawText`、`-FontColor`。
    *   **使用示例**：
        ```powershell
        pw2401 ff-masonry -Depth 1 -ColumnCount 3 -UniformCrop -CropSize 500
        ```
*   **`ff-svt` (SVT-AV1 高效 CPU 压制)**
    *   **描述**：调用极速 SVT 引擎进行高画质 AV1 编码。目标输出支持规避覆写后缀序号自增功能（不伤原文件）。
    *   **高光参数**：支持位置注入预设（如 `fast`, `ultra` 等快捷档位）、`-Preset`、`-CRF`。
    *   **使用示例**：
        ```powershell
        pw2401 ff-svt fast
        pw2401 ff-svt -Preset 5 -CRF 32
        ```
*   **`ff-nv-av1` (NVENC 硬件加速压制)**
    *   **描述**：调用 NVIDIA RTX 显卡进行狂暴硬件 AV1 编码，处理速度惊人。
    *   **使用示例**：`pw2401 ff-nv-av1`
*   **`ff-vmaf` (视频画损度 VMAF 分析测试)**
    *   **描述**：对两份源与目标目录内的视频做逐帧 VMAF 跑分算法对决，支持灵活输出图表和横向竖向的直观统计报告。
    *   **使用示例**：`pw2401 ff-vmaf <SourceDir> <TargetDir>`
*   **`ff-info`**
    *   **描述**：超高速探嗅媒体流指纹及关键信息。
*   **`ff-version`**
    *   **描述**：检查并输出底层 FFmpeg 版本与库文件能力。

### 📂 自动化文件清理与智能重构
告别凌乱文件，一键处理海量目录的收纳与自动化重命名。

*   **`dir-group` (物理维度收纳分拣隔离)**
    *   **描述**：在指定的 `Depth` 遍历层次内，扫描散落文件，并基于物理属性（是否为图片 `P`、视频 `V`、视频时长长短 `D`，文件大小 `S`）等边界维度，自动组建对应标尺的收纳文件夹（如 `V_1h-3h`）并实施安全转移。
    *   **使用示例**：
        ```powershell
        pw2401 dir-group -Depth 1 -Groups P,V,D,S
        ```
*   **`dir-tag` (自动化元数据智能挂载标签)**
    *   **描述**：递归下钻分析各文件夹内的多媒体容量和形态。智能将诸如 `[12P 2V 4.5GB]` 的纯净摘要挂在旧有或空白目录名末尾（若某特征不存在则自动隐去）。
    *   **高光参数**：`-Depth` (决定扫到深度的粒度)、`-ReplaceLastTag`（可覆盖清除无意义旧尾标）、`-Format`。
    *   **使用示例**：
        ```powershell
        pw2401 dir-tag -Depth 1 -ReplaceLastTag
        ```
*   **`dir-zip` (自动探测智能隔离压缩)**
    *   **描述**：自动对同级下 N 个深度的每个文件夹独立执行 `.zip` 或 `.cbz` 一次性打包防泄露。
    *   **高光参数**：`-Depth`、`-IncludeBaseFolder`（是否保持父底包结构）、`-Extension`。
    *   **使用示例**：
        ```powershell
        pw2401 dir-zip -Depth 1 -Extension .cbz -IncludeBaseFolder
        ```
*   **`hard-link` (镜像硬链接工厂)**
    *   **描述**：完美复原 `WorkDir` 的目录结构，并不损毁性地在目标文件夹创造全套硬链接映射。零额外物理盘耗存，极其适合做中转分类跳板。
    *   **使用示例**：`pw2401 hard-link`
*   **`dir-info`**：高级查阅目录下海量层级的详细空间穿透视图。
*   **`dir-trim` / `dir-void`**：深度强迫症级空目录与临时碎片清理大师。

### ⚙️ 后台服务与生态系统工具
*   **`sys-install`**（别名 `install`）：核心环境变量注册模块（包含路径保护功能防清零）。
*   **`sys-help`**（别名 `help`）：显示帮助及全部兼容别名。
*   **`sys-docs`**（别名 `docs`）：重新生成注释帮助文档。
*   **`SystemInfo`**：轻量级探测当前处理器、显卡型号与内存池资源，适配排障。
*   **`sys-status`**（别名 `status`）：检查程序及依赖组件可用情况。

---

## 📖 进阶配置与避坑说明

*   **获得专属命令帮助**：大部分主要命令配套了独立解释手册，运行 `pw2401 <命令>` 未带特定必选参数或者查看 `functions/` 目录下的 `.help.txt` 均可了解更多隐性高级参数玩法。
*   **模块定制 (`config.json`)**：项目支持配置 `WorkDir` 或后端挂载的固定依赖套件路径（例如全局注册你的系统默认 FFmpeg）。
*   **日志系统 (`sys-debug-log.ps1`)**：脚本采用分级与带有终端颜色的回显拦截体系 `Log-Message`，并会在目录留下详细运行轨迹如 `dir-group_2026xxxx.log`，查证方便。

## 📄 许可说明
本项目汇聚了日常繁冗数据整理工作流程的最佳实践，以供个人效率提升。在使用 FFmpeg 等第三方工具时，请严格遵守其相应的开源协议。

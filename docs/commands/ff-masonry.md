<!-- Generated from functions/ff-masonry.ps1. Do not edit directly. -->

# ff-masonry

使用 FFmpeg 将多张图片拼接为瀑布流长图。

## 用法

```powershell
pw2401 ff-masonry [-CanvasWidth <int>] [-ColumnCount <int>] [-ReverseColumn <switch>] [-Tolerance <double>] [-Gap <int>] [-BackgroundColor <string>] [-ShowFileName <switch>] [-FontSize <int>] [-Sort <string>] [-Depth <int>] [-CropSize <string>] [-JpegQuality <int>]
```

## 说明

扫描指定深度的图片目录，根据原始比例计算缩放和列布局，生成单张 JPEG 瀑布流图片。
支持智能排序、统一裁剪、文字标签、列反转、背景颜色和调试布局数据。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-CanvasWidth` | `int` | 否 | 3000 | 输出画布的总宽度，单位为像素。 |
| `-ColumnCount` | `int` | 否 | 5 | 瀑布流列数。 |
| `-ReverseColumn` | `switch` | 否 | — | 将每一列中的图片顺序反转。 |
| `-Tolerance` | `double` | 否 | 0.5 | 智能布局允许的高度容差系数。 |
| `-Gap` | `int` | 否 | 0 | 图片之间的间距，单位为像素。 |
| `-BackgroundColor` | `string` | 否 | "white" | FFmpeg 支持的背景颜色名称或十六进制颜色。 |
| `-ShowFileName` | `switch` | 否 | $false | 在图片上绘制源文件名。 |
| `-FontSize` | `int` | 否 | 20 | 文件名文字大小。 |
| `-Sort` | `string` | 否 | "Smart" | 排序方式：Smart、Name 或 VerticalRatio。 |
| `-Depth` | `int` | 否 | 0 | 要处理的精确目录深度。0 表示当前目录。 |
| `-CropSize` | `string` | 否 | "" | 统一裁剪尺寸，可以为空、Auto 或 WidthxHeight 格式。 |
| `-JpegQuality` | `int` | 否 | 2 | FFmpeg JPEG 质量参数，数值越小质量越高。 |

## 依赖

ffmpeg, ffprobe

## 示例

### 示例 1：three-columns

```powershell
pw2401 ff-masonry -ColumnCount 3 -CanvasWidth 960 -Gap 4
```

将当前目录中的测试图片拼成三列、总宽度 960 像素的瀑布流。

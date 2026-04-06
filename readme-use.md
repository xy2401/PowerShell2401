





# ff-masonry

使用 FFmpeg 实现瀑布流图片拼接。
将多张图片拼接成符合指定宽度和列数的瀑布流长图。

```powershell
# 1. 在当前目录下处理
pw2401 ff-masonry

# 2. 自定义参数
pw2401 ff-masonry -ColumnCount 3 -CanvasWidth 1920 -BackgroundColor "black" -Gap 10

# 3. 开启统一裁剪（自动计算尺寸众数）
pw2401 ff-masonry -CropSize "Auto"

# 4. 指定裁剪尺寸
pw2401 ff-masonry -CropSize "1920x1080"
```

# ff-svt.ps1

https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Ffmpeg.md



```bash

# Example 1: Fast/Realtime Encoding
ffmpeg -i infile.mkv -c:v libsvtav1 -preset 10 -crf 35 -c:a copy outfile.mkv

# Example 2: Encoding for Personal Use
ffmpeg -i infile.mkv -c:v libsvtav1 -preset 5 -crf 32 -g 240 -pix_fmt yuv420p10le -svtav1-params tune=0:film-grain=8 -c:a copy outfile.mkv

```

 
 
# ff-vmaf

**第一种玩法（极简模式，连参数名都不用打）：**
因为我给 `$EncodedDirs` 设置了动态吸收剩余参数的特性（`ValueFromRemainingArguments = $true`），所以你直接这么打，**不需要加逗号，也不需要写参数名**，超级丝滑：
```powershell
pw2401 ff-vmaf 1 1.ffsvt 1.ffnv
```
系统会自动把 `1` 赋给 `SourceDir`，把 `1.ffsvt 1.ffnv`（甚至后面排更长）全盘吃下变成数组塞给 `EncodedDirs`。这是最推荐、最省事的用法！

**第二种玩法（你的严格指名模式）：**
如果你更喜欢显式地指定参数名 `-SourceDir 1 -EncodedDirs`，这也是完全兼容支持的！**但需要注意的是：** 在 PowerShell 的语法规则里，当你显式点名一个参数并传入多个值时，必须要用**逗号（`,`）** 把它们连起来，而不能只用空格，否则 PowerShell 会把第二个路径当成是另一个你不关心的参数而报错。

所以你只需要加上逗号，就像这样：
```powershell
pw2401 ff-vmaf -SourceDir 1 -EncodedDirs 1.ffsvt, 1.ffnv
```
 
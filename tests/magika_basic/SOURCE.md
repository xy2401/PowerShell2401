# 测试素材来源

本目录是多文件格式测试夹具，来源于 Google Magika 仓库的
[`tests_data/basic`](https://github.com/google/magika/tree/main/tests_data/basic)。

- 上游项目：Google Magika
- 本地快照可见版本：约 0.5.0（精确上游 commit 未记录）
- 上游许可证：Apache-2.0
- 本项目用途：为复制、移动、压缩、类型识别、图片和媒体转换提供真实输入文件

测试执行器只能读取本目录。每个 `functions/*.psd1` 测试定义按需选择文件并复制到
当前执行目录的 `target/pw2401-tests/`，所有修改和生成结果都发生在该隔离副本中。

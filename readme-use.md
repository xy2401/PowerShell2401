# pw2401 使用文档

命令用法与示例已经迁移到各 `functions/*.ps1` 文件开头的 PowerShell 注释帮助，并自动生成到：

- [命令文档索引](docs/README.md)
- `pw2401 help`：终端快速帮助
- `pw2401 docs`：重新生成 Markdown 文档
- `pw2401 test`：执行纯 PowerShell 示例测试
- `pw2401 test -External`：同时执行外部依赖示例测试

系统和调试脚本统一使用 `sys-` 文件名前缀。入口保留原短命令作为别名，例如 `help -> sys-help`、`install -> sys-install`、`docs -> sys-docs`。

请修改命令脚本中的注释帮助，不要直接编辑 `docs/commands/*.md`。

可执行示例通过注释中的 `# ExampleId:` 与同目录、同名的 `functions/*.psd1` 测试定义绑定。PSD1 只声明输入和预期结果，实际执行命令始终来自 `.EXAMPLE`。

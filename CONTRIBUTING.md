# Contributing

感谢参与改进 Windows Java + IDEA 一键安装。

## 架构约束

1. 只支持 Windows 10 / 11 x64。
2. 网页保持纯静态 HTML/CSS，只做桌面布局，不做手机端适配，不引入运行时 JavaScript、CDN 或后端接口。
3. `scripts/install-windows.bat` 必须保持单文件自包含，不能依赖第二层下载器。
4. 不恢复环境检测、检测报告、修复桥、进度服务、JSON 回传或 macOS 脚本。
5. 只从 Adoptium 和 JetBrains 官方 HTTPS 地址下载安装包。
6. 安装包必须校验官方 SHA-256，校验失败时不得执行安装器。
7. 除 Java MSI 权限外，不扩大管理员权限范围；不静默结束用户进程。

## 提交前

```powershell
pwsh -File tests/installer-contract.ps1
```

如果修改 BAT，额外确认：

- 文件在 Windows PowerShell 5.1 下可解析。
- `--dry-run` 返回码为 `0`。
- 成功返回 `0`、失败返回 `1`、用户取消返回 `2`。
- 下载目录位于所选安装根目录内，清理前必须验证路径边界。

## Pull Request

请说明：

- 修改了哪个固定版本或官方下载来源。
- 是否改变安装路径、权限、环境变量或桌面快捷方式。
- 执行过的 Windows 手动测试。
- 是否需要升级失败回滚说明。

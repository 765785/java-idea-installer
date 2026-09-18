# Contributing

感谢参与改进 Windows Java + IDEA 一键安装。

## 架构约束

1. 只支持 Windows 10 / 11 x64。
2. 网页保持纯静态 HTML/CSS，只做桌面布局，不做手机端适配，不引入运行时 JavaScript、CDN 或后端接口。
3. `scripts/install-windows.bat` 必须保持单文件自包含，不能依赖第二层下载器。
4. 不恢复环境检测、检测报告、修复桥、进度服务、JSON 回传或 macOS 脚本。
5. 安装包可优先从清华、南大等 HTTPS 镜像传输，但必须使用 Adoptium 或 JetBrains 官方校验值，并保留官方来源回退。
6. 安装包必须校验官方 SHA-256，校验失败时不得执行安装器。
7. 管理员权限仅用于 Java MSI 和必要的机器级 `JAVA_HOME`、`PATH` 修正，且应在同一次 UAC 中完成；不静默结束用户进程。
8. 安装前必须先检测并复用已有的兼容 JDK 21 和 IDEA `2025.2.6.2`，不得重复下载或覆盖。

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

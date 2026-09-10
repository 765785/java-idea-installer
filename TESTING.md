# 手动测试清单

本项目不使用 Playwright。前端功能在真实浏览器中手动核对，CI 只执行轻量静态检查，并且不会安装或卸载任何软件。

## 前端

- 在 Windows 浏览器的普通与隐私窗口中打开站点，确认显示 `Windows 10 / 11`。
- 在 macOS 或设备模拟器中使用 Safari/Chrome 访问，确认系统识别与架构提示合理。
- 修改 User-Agent 或使用不支持的浏览器，确认显示“暂未支持自动安装”。
- 切换深色/浅色主题并刷新页面，确认 `localStorage` 保持用户选择。
- 依次拖动合法 JSON、选择非法 JSON、上传超过 1 MB 的文件，确认正常渲染或显示明确错误。
- 使用带 `#result=<base64url>` 的地址打开页面，确认自动解析并滚动到检测报告。
- 构造超长 `#result`，确认页面提示改用 JSON 上传。
- 导入缺失组件、版本过低和健康问题的报告，确认状态颜色、汇总数量与修复按钮正确。
- 点击“一键修复”，确认显示对应平台的 `--fix` 命令，并能复制命令。
- 检查卸载说明与脚本实际行为：只有输入 `DELETE` 才继续彻底清理。
- 在常见桌面浏览器宽度（1366px、1440px、1920px）检查：无横向溢出、无文字遮挡、无按钮换行错位、控件没有浏览器默认字号。

## 本地进度页

- 设置 `JAVA_SETUP_NO_UI=0`，运行安装脚本的测试副本，确认系统默认浏览器自动打开进度页。
- 确认 `progress.html` 每两秒请求 `progress.json`，进度、当前步骤和日志随 JSON 更新。
- 安装完成后确认出现“返回网页查看最终报告”，URL 带 `#result=<base64url>`。
- 停止本地服务后确认进度页显示连接提示，而不是空白或无限加载。

## Windows

- 在当前 PowerShell 中解析全部 `.ps1` 文件，确认没有语法错误。
- 双击 `detect.bat`，确认中文/英文 Windows 均可生成 `detection_result.json`。
- 构造 `JAVA_HOME` 缺失、指向错误目录、低于 JDK 25、存在多个 JDK 四种情况，核对检测状态。
- 断开网络后检测，确认网络字段为不可用或部分可用，且不会阻断本地 IDEA 识别。
- 仅在虚拟机中运行安装测试，确认 UAC 只在实际安装步骤出现。
- 检查卸载确认：输入不是 `DELETE` 时不得删除任何内容。

## macOS

- 运行 `bash -n` 和 ShellCheck，确认无语法或常见 shell 问题。
- 在 Intel 与 Apple 芯片至少各验证一次 `detect.command`。
- 在没有 Homebrew 的环境确认 Adoptium 官方 pkg 兜底路径。
- 确认 Homebrew 相关步骤在普通用户下运行，仅在需要写 `/Applications` 或安装 pkg 时请求 `sudo`。
- 检查被 Gatekeeper 隔离的应用能通过“一键修复”移除 quarantine 属性。
- 彻底卸载测试必须同时确认设置目录被删除、任何项目源码目录保持不变。

## 发布验收

- GitHub Actions 的 `Static checks` 和 `Deploy GitHub Pages` 全部成功。
- 公开站点返回 HTTP 200，下载两个 ZIP 均包含脚本、`progress.html`、`progress.js` 和对应 `lib`。
- 仓库中不存在 API Key、个人路径、个人检测报告或生成工作流明文密钥。
- `README.md` 截图与当前页面一致。

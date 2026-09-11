# Java 一键搭建

面向 Java 新手的 Windows 与 macOS 环境工具：自动检测系统环境，引导安装 JDK 25 LTS 和最新版 IntelliJ IDEA Community，并完成 `JAVA_HOME`、`PATH` 与 `Hello World` 验证。

本项目按桌面浏览器使用场景交付，当前不单独适配手机或平板布局。

![Java 一键搭建桌面端](assets/screenshots/desktop.png)

公开网址：[https://765785.github.io/java-idea-installer/](https://765785.github.io/java-idea-installer/)

## 功能

- 🔍 自动识别 Windows、macOS 或不支持的系统。
- ☕ 检测 JDK、IDEA 与 `JAVA_HOME`，生成 UTF-8 JSON 报告。
- 🧩 运行时查询 winget 与 Homebrew 中的 Temurin 包，不写死包 ID。
- 🚀 winget/brew 无法提供 JDK 25 或 IDEA 最新版时，回退到官方安装包并校验 SHA-256。
- 🛡️ 最小权限执行：只有实际安装步骤才触发 UAC 或 `sudo`，Homebrew 不以 root 运行。
- 📈 修复终端和进度文件会持续更新，完成后自动回传最终报告。
- 🧪 安装完成后自动编译并运行 `Hello World`。
- 🛠️ 一个“一键修复全部”按钮处理 `JAVA_HOME`、`PATH`、多 JDK、IDEA 损坏、Gatekeeper 和 VC++ Runtime；端口占用只提示。
- 🔐 临时本地修复助手只监听 `127.0.0.1`，使用随机端口和一次性令牌，30 分钟后自动退出。
- 🧹 卸载默认彻底清理 IDEA、目标 JDK 与 JetBrains 用户配置，但不会删除项目源码。
- 🌗 网页支持深色/浅色主题，并使用 `localStorage` 记忆选择。

## 使用方法

1. 打开公开网页，点击“下载并开始”。
2. Windows 下载后双击 `detect.bat`；macOS 下载后双击 `detect.command`。
3. 启动器自动下载并校验完整工具包，然后打开检测报告。
4. 点击“一键修复全部”并确认，终端会自动安装、配置和验证。
5. 完成后网页自动打开最终报告，无需再运行安装或验证脚本。

浏览器不能静默执行本机程序，因此“一键”始终包含一次明确的手动运行或系统授权。

单文件启动器会自动下载官方工具包、核对 `SHA256SUMS.txt` 后再继续执行，不需要手动解压。完整 ZIP 仍保留在下载面板的“高级调试”入口。

## 支持范围

| 项目 | Windows | macOS |
| --- | --- | --- |
| 系统 | Windows 10 / 11 | 当前受 Homebrew 支持的 macOS |
| JDK | Temurin 25 LTS | Temurin 25 LTS |
| IDEA | Community 最新版 | Community 最新版 |
| 架构 | x64 | Intel / Apple 芯片 |

## 安全说明

- 网页只读取浏览器公开信息；本地检测结果通过 URL 片段或用户选择的 JSON 文件回传。
- 本地修复助手只接受随机令牌和固定 `fix-all` 请求，网页不能传入任意路径或命令。
- 修复请求在当前页面通过隐藏的本地通道提交，不会额外打开新的标签页。
- 安装脚本查询 JetBrains 官方发布接口，并在网络失败时标注“无法确认最新版”，不会阻断已有 IDEA 的使用。
- JDK 与 IDEA 官方安装包均核对官方 SHA-256 后才执行。
- 终端会列出即将修改的环境变量和目录。Homebrew 不会以 root 身份安装。
- 彻底卸载必须输入 `DELETE`，且不会删除你的 Java 项目源码目录。

## 常见问题

### 为什么网页不能直接安装？

浏览器安全模型不允许网页读取完整本机软件列表或静默运行安装程序。首次需要下载并双击一次启动器，之后检测、环境修复、安装和验证会自动衔接。

### 为什么默认安装 JDK 25，而不是 17？

JDK 25 是当前新项目可用的 LTS。已有高版本 JDK 会被保留；脚本只把满足条件的最高版本设为默认 `JAVA_HOME`。

### IDEA 显示无法确认最新版怎么办？

表示 JetBrains 官方接口暂时不可访问。已经安装的 IDEA 会按可用状态处理，不会因为网络问题中断整个环境检测。

### 卸载会删除我的项目吗？

不会。脚本只清理 IDEA 程序、目标 JDK 和 JetBrains 设置、缓存、插件及最近项目记录，不会遍历或删除你的源码目录。

## 本地开发

启动静态站点：

```bash
python -m http.server 8000
```

访问 `http://127.0.0.1:8000/`。构建下载包：

```bash
scripts/package-toolkits.sh
```

下载包生成后会同时生成 `_site/downloads/SHA256SUMS.txt`，可用于核对 ZIP 完整性。

Windows 检测脚本可直接运行：

```powershell
.\scripts\detect.bat
```

macOS 检测脚本：

```bash
chmod +x scripts/*.sh scripts/*.command
./scripts/detect.sh
```

测试清单见 [TESTING.md](TESTING.md)。提交前不要求安装 Playwright；CI 只做 PowerShell 解析、批处理入口调用、Bash 语法和 ShellCheck。

## 贡献

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。不要提交 API Key、个人检测报告、安装日志或包含用户路径的截图。

## License

[MIT](LICENSE)

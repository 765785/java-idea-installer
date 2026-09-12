# 测试清单

项目只支持 Windows 10 / 11 x64，网页只提供桌面布局。不包含手机端适配、浏览器自动化、macOS 或环境检测流程。

## 自动检查

在仓库根目录运行：

```powershell
pwsh -File tests/installer-contract.ps1
```

该测试会检查：

- `index.html` 只暴露一个 `install-windows.bat` 下载入口。
- `styles.css` 使用固定桌面画布且不包含移动端断点。
- BAT 内嵌 PowerShell 能通过 PowerShell 5.1 语法解析。
- `--dry-run` 能识别已有 JDK 25 和 IDEA `2025.2.6.2`，并跳过下载。
- `--dry-run --ignore-existing` 能解析 Adoptium JDK 25 MSI。
- `--dry-run --ignore-existing` 能解析 JetBrains IDEA `2025.2.6.2` 和官方 SHA-256。
- 旧检测、报告、修复桥、进度服务、macOS 和打包文件已删除。

单独运行：

```powershell
cmd /d /c "scripts\install-windows.bat --dry-run"
```

忽略本机已有安装：

```powershell
cmd /d /c "scripts\install-windows.bat --dry-run --ignore-existing"
```

## Windows 虚拟机验收

- 在干净 Windows 11 x64 中选择 C 盘安装，确认路径为 `%USERPROFILE%\JavaDev`。
- 在已安装兼容 JDK 25 和 IDEA `2025.2.6.2` 的机器上运行，确认不访问下载源、不重复安装，并复用原目录。
- 在至少存在两个固定磁盘的虚拟机中选择 D 盘安装，确认内容位于 `D:\JavaDev`。
- 确认 Java MSI 只请求一次 UAC，IDEA 安装不额外请求管理员权限。
- 确认 `java -version` 和 `javac -version` 可用。
- 确认机器级或用户级 `JAVA_HOME` 指向 `<安装根目录>\jdk-25`。
- 确认 `PATH` 包含 `<安装根目录>\jdk-25\bin`。
- 确认桌面存在 `IntelliJ IDEA 2025.2.6.2.lnk`。
- 确认快捷方式指向 `<安装根目录>\idea-2025.2.6.2\bin\idea64.exe`。
- 确认安装成功后 IDEA 自动打开。

## 错误场景

- 所有固定磁盘剩余空间都低于 6 GB 时给出明确错误。
- 断网或下载失败时最多重试 4 次。
- JDK 或 IDEA 的 SHA-256 不匹配时不得运行安装器。
- 用户拒绝 UAC 时退出码为 `1`，并提示权限被取消。
- 用户选择取消已有组件处理时退出码为 `2`。
- IDEA 正在运行时停止安装并提示先关闭 IDEA。
- 选择不可写盘符时提示选择其他盘。
- 重复运行时分别验证 JDK 和 IDEA 的“跳过、重新安装、取消”。

## 发布验收

- GitHub Pages 部署成功，网页按钮下载文件名是 `install-windows.bat`。
- 下载文件可独立运行，不依赖仓库中的其他脚本或工具包。

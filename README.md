# Windows Java + IDEA 一键安装

面向 Windows 10 / 11 x64 的最小安装器。用户在网页下载一个 BAT 文件并双击后，安装器会自动：

- 安装 Eclipse Adoptium 最新 JDK 25 LTS。
- 安装 IntelliJ IDEA Community `2025.2.6.2`。
- 配置 `JAVA_HOME` 和 `PATH`。
- 在桌面创建 IDEA 快捷方式。
- 验证 `java`、`javac` 和 IDEA 启动器，并自动打开 IDEA。

网页只提供桌面布局，不做手机端适配。

公开网址：[https://765785.github.io/java-idea-installer/](https://765785.github.io/java-idea-installer/)

## 使用流程

1. 打开网页并点击“下载 Windows 安装器”。
2. 双击下载的 `install-windows.bat`。
3. 从列表中选择安装盘。
4. 接受一次 Java MSI 所需的管理员权限确认。
5. 等待安装完成，IDE 会自动打开。

浏览器不允许网页直接运行本机程序，因此必须保留一次手动双击。

## 安装位置

安装器只询问一次盘符：

| 选择 | 安装根目录 |
| --- | --- |
| C 盘 | `%USERPROFILE%\JavaDev` |
| 其他盘 | `<盘符>:\JavaDev` |

固定子目录：

- Java：`<安装根目录>\jdk-25`
- IDEA：`<安装根目录>\idea-2025.2.6.2`
- 安装日志：`<安装根目录>\java-install.log` 和 `idea-install.log`

如果目标目录中已经存在对应程序，安装器会逐项询问“跳过、重新安装或取消”。

## 空间与权限

- 至少需要 6 GB 可用空间。
- Java MSI 约 116 MB，IDEA 安装包约 993 MB。
- Java 使用官方 MSI 标准安装，会触发一次 UAC。
- IDEA 按当前用户安装，不修改 PATH、右键菜单或文件关联。
- 安装器不会卸载其他位置的 Java 或 IDEA。

## 官方来源

- JDK：Eclipse Adoptium API 返回的最新 JDK 25 Windows x64 MSI。
- IDEA：JetBrains 官方 `ideaIC-2025.2.6.2.exe`。

两个安装包都使用官方 SHA-256 校验。校验失败时不会运行安装器。

## 本地开发

执行契约测试：

```powershell
pwsh -File tests/installer-contract.ps1
```

只解析官方版本、盘符和 URL，不下载或安装：

```powershell
cmd /d /c "scripts\install-windows.bat --dry-run"
```

本地预览静态网页：

```bash
python -m http.server 8000
```

访问 `http://127.0.0.1:8000/`。

## 卸载

Java 和 IDEA 都是标准安装，可从 Windows“设置 > 应用 > 已安装的应用”卸载。项目源码不会被安装器读取或删除。

## License

[MIT](LICENSE)

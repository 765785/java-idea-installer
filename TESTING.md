# 测试清单

项目只支持 Windows 10 / 11 x64，网页只提供桌面布局。不包含手机端适配、浏览器自动化、macOS 或环境检测流程。

完整从零安装只在一次性 Windows Sandbox 中执行，不删除或修改宿主机已有的 Java 和 IDEA。

## 自动检查

在仓库根目录运行：

```powershell
pwsh -File tests/installer-contract.ps1
```

预期输出：

```text
installer contract checks passed
```

该测试会检查：

- `index.html` 只暴露一个 `install-windows.bat` 下载入口。
- `styles.css` 使用固定桌面画布且不包含移动端断点。
- BAT 内嵌 PowerShell 能通过 PowerShell 5.1 语法解析。
- `--dry-run` 能识别已有 JDK 25 和 IDEA `2025.2.6.2`，并跳过下载。
- `--dry-run --ignore-existing` 能解析 Adoptium JDK 25 MSI。
- `--dry-run --ignore-existing` 能解析 JetBrains IDEA `2025.2.6.2` 和官方 SHA-256。
- 旧检测、报告、修复桥、进度服务、macOS 和打包文件已删除。

## 本机非破坏预检

在本机运行：

```powershell
cmd /d /c "scripts\install-windows.bat --dry-run"
```

已有兼容版本时，预期输出包含：

```text
Found Eclipse Temurin JDK 25
Found IntelliJ IDEA Community 2025.2.6.2
Existing compatible versions will be reused. No download is needed.
```

从公开网页下载 BAT 后，只运行预检：

```powershell
$download = "$env:USERPROFILE\Downloads\install-windows.bat"
(Get-FileHash -Algorithm SHA256 -LiteralPath $download).Hash
cmd /d /c "`"$download`" --dry-run"
```

公开版本同样应识别已有环境，不访问下载源。记录 BAT 的 SHA-256。

## Windows Sandbox 验收

### 准备

1. 使用管理员 PowerShell 启用 Windows Sandbox：

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All
```

2. 重启电脑，从开始菜单启动 `Windows Sandbox`。
3. 每次重新打开 Sandbox 都会得到全新环境；失败场景应分别使用新的 Sandbox。

验收前记录：

| 项目 | 记录 |
| --- | --- |
| 测试日期 | |
| Git 提交 | |
| Sandbox 系统版本 | |
| 下载文件名 | |
| BAT SHA-256 | |
| UAC 次数 | |
| 最终退出码 | |

### 核心从零安装

1. 在 Sandbox 的 Edge 中打开 [https://765785.github.io/java-idea-installer/](https://765785.github.io/java-idea-installer/)。
2. 点击“下载 Windows 安装器”，确认文件名是 `install-windows.bat`。
3. 记录下载 BAT 的 SHA-256，然后双击运行。
4. 选择 C 盘，等待安装完成。

预期结果：

- Java MSI 只请求一次 UAC。
- Java 位于 `%USERPROFILE%\JavaDev\jdk-25`。
- IDEA 位于 `%USERPROFILE%\JavaDev\idea-2025.2.6.2`。
- 桌面存在 `IntelliJ IDEA 2025.2.6.2.lnk`。
- IDEA 安装完成后自动打开。

在安装后新开命令提示符并检查：

```bat
echo %JAVA_HOME%
java -version
javac -version
where java
where javac
```

预期 `java` 和 `javac` 均为 JDK 25，`JAVA_HOME` 指向 `%USERPROFILE%\JavaDev\jdk-25`，末尾不包含 `\bin`。

在 PowerShell 中检查文件和快捷方式：

```powershell
Test-Path "$env:USERPROFILE\JavaDev\jdk-25\bin\java.exe"
Test-Path "$env:USERPROFILE\JavaDev\idea-2025.2.6.2\bin\idea64.exe"
Test-Path "$env:USERPROFILE\JavaDev\.downloads"

$shortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "IntelliJ IDEA 2025.2.6.2.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath
```

预期前两项为 `True`，`.downloads` 为 `False`，快捷方式目标为 `%USERPROFILE%\JavaDev\idea-2025.2.6.2\bin\idea64.exe`。

### 重复运行

1. 关闭自动打开的 IDEA。
2. 再次双击同一个 `install-windows.bat`。

预期结果：

- 检测到已有 JDK 25 和 IDEA `2025.2.6.2`。
- 输出 `Existing compatible versions will be reused. No download is needed.`。
- 不访问下载源，不出现 UAC，不重复安装。
- 快捷方式被刷新，IDEA 再次打开。
- 不再包含要求选择“跳过、重新安装或取消”的旧流程。

### 断网下载失败

在全新的 Sandbox 中，使用管理员 PowerShell 添加入站无效映射：

```powershell
$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
Add-Content -LiteralPath $hosts -Value "0.0.0.0 github.com"
Add-Content -LiteralPath $hosts -Value "0.0.0.0 release-assets.githubusercontent.com"
```

从命令提示符运行并记录退出码：

```bat
"%USERPROFILE%\Downloads\install-windows.bat" --ignore-existing --no-launch
echo %ERRORLEVEL%
```

预期最多出现 4 次外层下载尝试，随后提示下载失败。退出码应为 `1`，不得执行 Java 或 IDEA 安装器。

### 拒绝 UAC

1. 使用全新的 Sandbox，正常运行公开 BAT。
2. Java MSI 下载完成后，在 UAC 提示中点击“否”。
3. 在命令提示符中检查退出码：

```bat
echo %ERRORLEVEL%
```

预期显示管理员权限被取消，退出码为 `1`，不安装 IDEA，也不创建桌面快捷方式。

### SHA-256 校验失败

在全新 Sandbox 中创建一个只用于测试的 BAT 副本，将 Java 下载地址替换为很小的官方响应，并强制使用错误校验值：

```powershell
$sourcePath = "$env:USERPROFILE\Downloads\install-windows.bat"
$testPath = "$env:TEMP\install-windows-badsha.bat"
$source = Get-Content -LiteralPath $sourcePath -Raw
$old = '$javaPackage = if ($javaAction -eq "install") { Resolve-JavaPackage } else { $null }'
$new = @'
if ($javaAction -eq "install") {
    $resolved = Resolve-JavaPackage
    $javaPackage = [pscustomobject]@{
        Version = $resolved.Version
        SourceUri = $resolved.SourceUri
        Uri = "https://api.adoptium.net/v3/info/available_releases"
        Sha256 = ("0" * 64)
    }
} else {
    $javaPackage = $null
}
'@
if (-not $source.Contains($old)) {
    throw "Could not patch the checksum test copy."
}
[IO.File]::WriteAllText($testPath, $source.Replace($old, $new), (New-Object System.Text.UTF8Encoding($false)))
cmd /d /c "`"$testPath`" --ignore-existing --no-launch"
"ExitCode=$LASTEXITCODE"
```

预期提示 SHA-256 不匹配，退出码为 `1`，不执行安装器，也不出现 UAC。

## 代码审查项

以下分支无法在普通 Sandbox 中自然复现，不通过人为改造安装器来覆盖：

- 所有固定磁盘剩余空间都低于 6 GB 时，`Get-FixedDriveChoices` 返回空列表并停止。
- IDEA 正在运行时，只有缺少 IDEA 且需要全新安装时才在 `Install-Idea` 中阻止；复用已有 IDEA 的路径不适用。
- 选择不可写盘符时，`Ensure-RootDirectory` 必须给出明确错误并允许重新选择。

## 发布验收

- GitHub Actions 的 `Static checks` 和 `Deploy GitHub Pages` 均为成功。
- GitHub Pages 公开网页返回 HTTP `200`，按钮下载文件名是 `install-windows.bat`。
- 下载文件可独立运行，不依赖仓库中的其他脚本或工具包。
- 公开 BAT 与当前提交内容一致；Windows 检出时允许仅存在 CRLF/LF 换行差异。

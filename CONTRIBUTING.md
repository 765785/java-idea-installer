# Contributing

感谢参与改进 Java 一键搭建。

## 提交前

1. 保持网页继续使用原生 HTML/CSS/JavaScript，不引入运行时 CDN。
2. 修改脚本接口时同步更新 README、Schema 和 TESTING。
3. 不在仓库、日志、截图或 Issue 中提交 API Key、邮箱令牌、个人路径或个人检测报告。
4. 不新增依赖 Playwright 的测试；前端验收按 TESTING.md 手动执行。
5. 不在共享提交中修改 `progress.html` 的字段契约，除非同时更新 `schemas/install-progress.schema.json`。

## 本地检查

```bash
node --check app.js
node --check scripts/progress.js
bash -n scripts/*.sh scripts/*.command scripts/lib/common-functions.sh
shellcheck -s bash scripts/*.sh scripts/*.command scripts/lib/common-functions.sh
```

```powershell
$tokens = $null
$errors = $null
Get-ChildItem scripts -Recurse -Filter *.ps1 | ForEach-Object {
  [System.Management.Automation.Language.Parser]::ParseFile(
    $_.FullName,
    [ref]$tokens,
    [ref]$errors
  ) | Out-Null
  if ($errors.Count -gt 0) { throw "$($_.FullName) has syntax errors" }
}
```

## Pull Request

请在 PR 中说明：

- 修改的用户场景和平台。
- 执行过哪些手动测试。
- 是否改变 JSON 字段、退出码或下载包结构。
- 是否涉及删除、环境变量或权限行为；如果涉及，必须写清回滚方式。

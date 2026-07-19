# 发布流程

[English](release.en.md) | 中文

本文记录维护者发布公开版本时的建议流程。

## 版本准备

1. 确认 `Sources/SSHTunnelCore/AppVersion.swift` 中版本号正确。
2. 查询 GitHub Releases，以最近一个实际公开的 Release 为比较基线；中间只有标签、没有 Release 的版本不作为基线。
3. 将“未发布”内容归档到目标版本，更新 `CHANGELOG.md` 和 `CHANGELOG.en.md`，并保留空的“未发布”章节。
4. 根据 `<上一公开版本>...<目标版本>` 的提交和文件差异起草 Release 标题与正文，发布前先审核准确文本。
5. 确认 README、架构说明、分发说明和排障文档没有过期内容；历史验收记录中的旧版本号不得机械替换。
6. 删除或替换明显过时、会误导当前版本的截图和示例资产。
7. 检查示例 Host、IP、用户名和路径均为脱敏值；只使用 `example-*`、`203.0.113.0/24`、回环地址和其他明确保留的示例值。
8. 检查工作区没有把 `.vscode/`、`.DS_Store`、`dist/`、导出 JSON、日志、备份、临时文件或本机配置纳入提交。

## 本地验证

运行：

```bash
swift test
git diff --check
./scripts/build-app-bundle.sh /private/tmp/SSH\ Tunnel\ Manager.app
```

验证打包产物：

```bash
find /private/tmp/SSH\ Tunnel\ Manager.app/Contents/Resources -maxdepth 4 -print
plutil -p /private/tmp/SSH\ Tunnel\ Manager.app/Contents/Info.plist
codesign --verify --deep --strict /private/tmp/SSH\ Tunnel\ Manager.app
```

确认：

- App/Core 的本地化 resource bundle 存在于 `.app/Contents/Resources`。
- `CFBundleDevelopmentRegion` 为 `en`。
- `CFBundleLocalizations` 包含 `en` 和 `zh-Hans`。
- ad-hoc 签名验证通过。

## 生成分发包

运行：

```bash
./scripts/package-app.sh
```

产物位于：

```text
dist/SSH Tunnel Manager-<version>.zip
```

本地审核时还应执行 `unzip -t`、解压后的签名和版本校验，并生成 SHA-256；正式 Release 工作流会上传 zip 及对应的 `.sha256` 文件。

`dist/` 是构建产物目录，不提交到 Git。

## GitHub Release

仓库中的 `.github/workflows/release.yml` 会在推送 `v*` 标签后自动执行：

1. 校验标签格式，并确认标签版本与 `AppVersion.current` 一致。
2. 运行 `swift test`。
3. 调用 `scripts/package-app.sh` 生成 zip。
4. 验证 zip、应用包签名和 SHA-256。
5. 创建 GitHub Release，或在同一标签重跑时覆盖上传资产。

自动创建的 GitHub Release 应包含：

- 版本号和简短摘要。
- 主要变化列表。
- 已知限制：当前 zip 使用本机 ad-hoc 签名，没有 Developer ID notarization。
- 安装提示：首次打开可能需要在 Finder 右键选择“打开”，或在系统设置中允许。
- 上传 `dist/` 中生成的 zip 和对应的 SHA-256 文件。

自动生成的 notes 只能作为草稿。正式公开前应再次核对其比较基线、标题和正文；如果与审核稿不一致，应在不删除标签和资产的前提下更新 Release 元数据。

标签必须在包含 Release Workflow 的提交上创建。标签和版本不一致时，工作流会失败且不会发布资产。

如果标签推送后工作流因为 GitHub 暂时故障而失败，可以在 Actions 页面手工运行 `Release` 工作流，并填写已经存在的标签。不要删除并重建已经公开的标签来重试。

## 发布后检查

1. 下载 Release 中的 zip。
2. 解压并启动应用。
3. 在英文和简体中文系统语言下各做一次基本菜单检查。
4. 添加脱敏测试隧道，确认保存和编辑正常；点击删除后取消，确认配置仍然存在，再次删除并确认后检查配置已移除。

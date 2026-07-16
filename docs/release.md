# 发布流程

[English](release.en.md) | 中文

本文记录维护者发布公开版本时的建议流程。

## 版本准备

1. 确认 `Sources/SSHTunnelCore/AppVersion.swift` 中版本号正确。
2. 更新 `CHANGELOG.md` 和 `CHANGELOG.en.md`。
3. 确认 README、架构说明、分发说明和排障文档没有过期内容。
4. 检查示例 Host、IP、用户名和路径均为脱敏值。

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

- App/Core 的本地化 resource bundle 存在。
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

`dist/` 是构建产物目录，不提交到 Git。

## GitHub Release

创建 GitHub Release 时建议包含：

- 版本号和简短摘要。
- 主要变化列表。
- 已知限制：当前 zip 使用本机 ad-hoc 签名，没有 Developer ID notarization。
- 安装提示：首次打开可能需要在 Finder 右键选择“打开”，或在系统设置中允许。
- 上传 `dist/` 中生成的 zip。

## 发布后检查

1. 下载 Release 中的 zip。
2. 解压并启动应用。
3. 在英文和简体中文系统语言下各做一次基本菜单检查。
4. 添加脱敏测试隧道，确认保存和编辑正常；点击删除后取消，确认配置仍然存在，再次删除并确认后检查配置已移除。

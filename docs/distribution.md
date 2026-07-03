# 分发说明

[English](distribution.en.md) | 中文

## 适用场景

当前分发方式适合小范围给可信用户使用，例如朋友、同事或自己多台 Mac。它不依赖 Apple Developer Program，也不做 Developer ID notarization。

如果要公开面向大量用户分发，建议后续升级为 Developer ID 签名、notarization 和 DMG/Release 流程。

## 生成分发包

在仓库根目录运行：

```bash
./scripts/package-app.sh
```

脚本会执行以下步骤：

1. 使用 SwiftPM release 模式构建 `ssh-tunnel-manager`。
2. 生成 `SSH Tunnel Manager.app`。
3. 把 SwiftPM 生成的本地化 resource bundle 复制到 `.app/Contents/Resources`。
4. 写入 `Info.plist`，包含版本号、菜单栏应用标记、最低系统版本和 `en`、`zh-Hans` 本地化声明。
5. 使用本机 ad-hoc 签名。
6. 生成 zip 包到 `dist/`。

产物路径示例：

```text
dist/SSH Tunnel Manager-0.2.0.zip
```

`dist/` 是构建产物目录，不提交到 Git。

## 用户安装方式

把 zip 文件发给用户后，用户按以下方式安装：

1. 解压 `SSH Tunnel Manager-0.2.0.zip`。
2. 把 `SSH Tunnel Manager.app` 拖到 `/Applications`。
3. 从 Finder、Spotlight 或 Launchpad 打开应用。
4. 根据自己的 `~/.ssh/config` 添加隧道配置。

当前应用不会内置任何默认隧道，也不会保存 SSH 密码或私钥。

应用界面支持英文和简体中文，默认跟随用户的 macOS 系统语言；切换系统语言后需要重新启动应用。

## Gatekeeper 提示

当前 zip 包使用 ad-hoc 签名，不包含 Apple Developer ID notarization。用户第一次打开时，macOS 可能提示无法验证开发者。

常见处理方式：

- 在 Finder 中右键点击 `SSH Tunnel Manager.app`，选择“打开”。
- 如果仍被拦截，到“系统设置 > 隐私与安全性”中允许打开。

这适合小范围可信分发；如果希望用户双击即可顺滑打开，需要后续接入 Developer ID 签名和 notarization。

## 更新版本

### 更新本机已安装应用

在开发机或自己的 Mac 上更新 `/Applications/SSH Tunnel Manager.app` 时，在仓库根目录运行：

```bash
./scripts/install-app.sh
```

脚本会重新执行 release 构建、生成 `.app`、做本机 ad-hoc 签名，并覆盖：

```text
/Applications/SSH Tunnel Manager.app
```

如果旧版本仍在菜单栏运行，需要先在应用里点“退出”，再重新打开应用。可以从 Finder、Spotlight、Launchpad 打开，也可以运行：

```bash
open -a 'SSH Tunnel Manager'
```

### 更新分发包

需要发给其他用户时，代码更新后重新运行：

```bash
./scripts/package-app.sh
```

把新的 zip 发给用户。用户关闭旧版本应用后，用新版本覆盖 `/Applications/SSH Tunnel Manager.app` 即可。

隧道配置保存在：

```text
~/Library/Application Support/ssh-tunnel-manager/tunnels.json
```

覆盖应用不会删除用户已有隧道配置。

## 隧道配置说明

应用支持三种模式：

- 手动转发：应用生成 `ssh -N -L localHost:localPort:remoteHost:remotePort sshHost`。
- 动态 SOCKS：应用生成 `ssh -N -D localHost:localPort sshHost`，适合临时给 Git、curl 或浏览器等工具指定 SOCKS 代理。
- SSH Config：应用只传入 `sshConfigName`，由用户自己的 `~/.ssh/config` 提供 `LocalForward`。

示例文档中只使用 `example-bastion`、`example-service` 和 `203.0.113.10` 这类脱敏值；分发给他人前不要把自己的真实 Host 别名、内网 IP、用户名或私钥路径写进公开文档。

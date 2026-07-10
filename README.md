# mac-ssh-tunnel-manager

[English](README.en.md) | 中文

用于管理 SSH 本地端口转发和动态 SOCKS 隧道的 macOS 菜单栏应用。

当前版本：`0.2.0`

应用名称为 `SSH Tunnel Manager`，SwiftPM executable target 为 `ssh-tunnel-manager`。

应用第一版保持轻量：

- 使用 SwiftUI `MenuBarExtra` 运行在菜单栏。
- 启动隧道时直接调用 `/usr/bin/ssh`，不经过 shell 字符串拼接。
- 复用系统已有的 `~/.ssh/config`、ssh-agent 和 macOS Keychain 行为。
- 隧道配置以 JSON 保存在本机。
- 不保存服务器密码或私钥。
- 不内置任何默认隧道配置。
- 界面支持英文和简体中文，默认跟随 macOS 系统语言。

## 界面截图

![中文隧道列表](docs/assets/screenshots/menu-zh-Hans.png)

![中文添加手动转发表单](docs/assets/screenshots/add-local-forward-zh-Hans.png)

## 环境要求

- macOS 14 或更高版本。
- Xcode 26 或兼容的 Swift 6 工具链。
- 如果要使用 SSH Config 模式，需要先在 `~/.ssh/config` 中配置对应 SSH Host。

## 运行

开发调试时可以直接运行：

```bash
swift run ssh-tunnel-manager
```

也可以用 Xcode 打开 `Package.swift`，运行 `ssh-tunnel-manager` executable target。

## 安装到应用程序

需要像普通 macOS 应用一样从 Finder、Spotlight 或 Launchpad 启动时，运行：

```bash
./scripts/install-app.sh
```

脚本会执行 release 构建，生成 `SSH Tunnel Manager.app`，进行本机 ad-hoc 签名，并安装到：

```text
/Applications/SSH Tunnel Manager.app
```

以后代码没有变化时，直接点击应用图标启动即可。更新代码后，再运行一次安装脚本覆盖安装新版。

如果菜单栏中旧版本仍在运行，覆盖安装后需要先在应用里点“退出”，再从 Finder、Spotlight、Launchpad 或命令行重新打开：

```bash
open -a 'SSH Tunnel Manager'
```

## 打包分发

小范围发给别人使用时，可以生成 zip 包：

```bash
./scripts/package-app.sh
```

产物会输出到：

```text
dist/SSH Tunnel Manager-0.2.0.zip
```

对方解压后，把 `SSH Tunnel Manager.app` 拖到 `/Applications`，再从 Finder、Spotlight 或 Launchpad 打开。

当前 zip 包使用本机 ad-hoc 签名，没有 Apple Developer ID notarization。第一次打开时 macOS 可能提示无法验证开发者，用户需要右键点击应用选择“打开”，或在“系统设置 > 隐私与安全性”中允许打开。

## 测试

```bash
swift test
```

## 文档

- [架构说明](docs/architecture.md)
- [分发说明](docs/distribution.md)
- [隐私说明](docs/privacy.md)
- [排障手册](docs/troubleshooting.md)
- [发布流程](docs/release.md)
- [更新日志](CHANGELOG.md)
- [贡献指南](CONTRIBUTING.md)
- [安全政策](SECURITY.md)
- [许可证](LICENSE)

## 配置文件

应用会把隧道定义写入：

```text
~/Library/Application Support/ssh-tunnel-manager/tunnels.json
```

每条隧道保存以下字段：

- `name`
- `mode`
- `sshHost`
- `localHost`
- `localPort`
- `remoteHost`
- `remotePort`
- `sshConfigName`
- `openURL`

首次启动时列表为空，需要在菜单栏界面中手动添加隧道。

## 使用方式

点击“添加隧道”后选择一种模式。以下示例均使用脱敏 Host 和保留地址，需要替换为自己 `~/.ssh/config` 中真实可用的 Host 别名。

### 手动转发

适合把远端某个固定服务映射到本机端口，例如远端 Web、数据库或管理端口。

```text
模式：手动转发
名称：Example Service
SSH Host：example-bastion
本地：127.0.0.1 18080
远端：127.0.0.1 8080
打开 URL：http://127.0.0.1:18080
```

如果本地监听地址不是回环地址，保存或启动时应用会先提示可能的局域网暴露风险，确认后才继续。

### 动态 SOCKS

适合临时给命令行工具或支持 SOCKS 的应用走 SSH 代理。应用只负责启动本地 SOCKS 监听，不会自动修改系统代理或 Git 配置。

```text
模式：动态 SOCKS
名称：Example SOCKS
SSH Host：example-bastion
SOCKS：127.0.0.1 1080
打开 URL：留空
```

启动后，需要使用 SOCKS 的命令或应用自行指定代理，例如：

```bash
ALL_PROXY=socks5h://127.0.0.1:1080 git fetch
```

建议将 SOCKS 监听地址保持为 `127.0.0.1`。如果使用非回环地址，应用会在保存或启动前要求确认，因为局域网设备可能访问这个代理。

### SSH Config

适合复用 `~/.ssh/config` 中已经写好的 `LocalForward`。应用只保存 Host 别名，不会自动编辑 SSH 配置。

```sshconfig
Host example-service
  HostName 203.0.113.10
  User appuser
  LocalForward 127.0.0.1:18080 127.0.0.1:8080
```

```text
模式：SSH Config
名称：Example Service
SSH Config：example-service
打开 URL：http://127.0.0.1:18080
```

## SSH 命令结构

手动转发模式下，应用从字段生成参数：

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -L localHost:localPort:remoteHost:remotePort \
  sshHost
```

SSH Config 模式下，应用直接使用 `~/.ssh/config` 中已有 Host：

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  sshConfigName
```

SSH Config 模式要求对应 Host 至少配置一条 `LocalForward`，例如：

```sshconfig
Host example-service
  HostName 203.0.113.10
  User appuser
  LocalForward 127.0.0.1:18080 127.0.0.1:8080
```

应用会检查解析后的 `LocalForward` 绑定地址；如果不是回环地址，保存或启动时会提示风险并要求确认。

在应用中选择 `SSH Config` 模式后，只需要填写：

```text
名称：Example Service
SSH Config：example-service
打开 URL：http://127.0.0.1:18080
```

动态 SOCKS 模式下，应用从字段生成 `-D` 参数：

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -D localHost:localPort \
  sshHost
```

应用只会停止自己启动的 SSH 进程，不会误杀用户手动打开的 SSH 连接。

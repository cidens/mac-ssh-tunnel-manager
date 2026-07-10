# 排障手册

[English](troubleshooting.en.md) | 中文

本文记录常见问题和排查方向。公开反馈时请先脱敏真实 Host、IP、用户名、私钥路径和完整 SSH 配置。

## 本地端口已被占用

现象：

```text
Address already in use
Could not request local forwarding.
```

原因通常是同一个本地地址和端口已经被其他进程监听，也可能是同一个隧道已经在另一个应用实例中启动。

排查：

```bash
lsof -nP -iTCP:<local-port> -sTCP:LISTEN
```

处理方式：

- 停止占用该端口的进程。
- 换一个本地端口。
- 确认没有同时运行多个 `SSH Tunnel Manager.app` 实例。

## 提示本地监听可能暴露

当手动转发、动态 SOCKS 或 SSH Config 的 `LocalForward` 使用非回环绑定地址时，应用会在保存或启动前提示风险。

默认建议使用：

```text
127.0.0.1
```

如果选择继续，局域网中的其他设备可能访问固定转发服务；动态 SOCKS 模式还可能被其他设备当作代理使用。只有确认需要局域网访问时才使用 `*`、`0.0.0.0` 或其他非回环地址。

## 命令行工具没有自动走 SOCKS

动态 SOCKS 模式只启动本地 SOCKS 监听，不会自动修改系统代理、浏览器代理或命令行工具配置。需要走 SOCKS 的命令应显式指定代理：

```bash
ALL_PROXY=socks5h://127.0.0.1:<local-port> curl https://example.com
```

其中 `<local-port>` 替换为应用中配置的本地端口。

如果某个命令仍直接连接目标服务，通常说明该命令没有读取代理环境变量，或应用自身需要单独配置代理。

## SSH Config 模式提示缺少 LocalForward

SSH Config 模式要求对应 Host 至少包含一条 `LocalForward`。示例：

```sshconfig
Host example-service
  HostName 203.0.113.10
  User appuser
  LocalForward 127.0.0.1:18080 127.0.0.1:8080
```

可以用以下命令检查 OpenSSH 最终解析结果：

```bash
ssh -G example-service | grep -i '^localforward '
```

如果没有输出，应用会拒绝保存或启动该配置。

## SSH Config 使用了 ProxyJump 或 Match exec

应用会运行 `ssh -G <Host>` 做保存前校验。复杂配置可能因为 `Match exec`、`ProxyJump` 或 DNS 较慢导致校验超时。

处理方式：

- 在终端运行 `ssh -G example-service`，确认是否很慢或报错。
- 简化 Host 配置后重试。
- 确认跳板机和 DNS 可达。

## 首次打开提示无法验证开发者

当前分发包使用本机 ad-hoc 签名，没有 Apple Developer ID notarization。首次打开可能被 Gatekeeper 拦截。

处理方式：

- 在 Finder 中右键点击 `SSH Tunnel Manager.app`，选择“打开”。
- 如果仍被拦截，到“系统设置 > 隐私与安全性”中允许打开。

## 切换系统语言后界面没有变化

应用跟随 macOS 系统语言，但不会运行时切换。切换系统语言后需要退出并重新启动应用。

## 应用退出时会关闭哪些 SSH

应用只关闭自己启动并记录的 SSH 进程，不会主动终止用户在终端里手动启动的 SSH 连接。

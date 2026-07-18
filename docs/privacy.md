# 隐私说明

[English](privacy.en.md) | 中文

`ssh-tunnel-manager` 是本地运行的 macOS 菜单栏工具。当前版本不包含账号系统、遥测、云同步或远程配置服务。

## 本地保存的数据

应用会把隧道配置保存到：

```text
~/Library/Application Support/ssh-tunnel-manager/tunnels.json
```

配置可能包含：

- 隧道名称。
- SSH Host 别名。
- 本地监听地址和端口。
- 远端地址和端口；远程转发模式下包括远端监听和本地目标。
- SSH Config Host 名称。
- 可选的打开 URL。
- 用户填写的标签、收藏状态和手工顺序。
- 最近一次成功启动 SSH 进程的本地时间。

全局快捷键设置独立保存到：

```text
~/Library/Application Support/ssh-tunnel-manager/settings.json
```

该文件只包含设置版本、是否启用、物理键码和修饰键集合。应用不会上传这些设置。

首次保存远程转发配置前，应用可能在同一目录创建 `tunnels.json.pre-remote-forward.bak`。该文件是旧隧道配置的本地恢复副本，包含与 `tunnels.json` 相同类型的信息，不会上传。

应用不会保存：

- SSH 密码。
- 私钥内容。
- token。
- ssh-agent 凭据。
- macOS Keychain 凭据。

应用通过 macOS 全局快捷键注册接口接收已配置的组合键，不持续监听或保存普通键盘输入。只有用户主动点击“录制”后，应用才临时读取当前按键状态并取得下一次组合键；录制完成、取消或设置窗口关闭后立即停止。该功能不需要辅助功能或输入监控权限。

## 网络行为

应用本身不主动连接第三方服务。启动隧道时，它会调用系统 `/usr/bin/ssh`，由 SSH 按用户填写的 Host 或 `~/.ssh/config` 发起连接。

动态 SOCKS 模式只启动本地 SOCKS 监听，不会自动修改系统代理、浏览器代理或 Git 配置。哪些流量经过隧道，由用户自己运行的命令或应用决定。

远程转发模式会请求 SSH 服务器建立远端监听，并把连接转发到 Mac 本机或 Mac 可访问的目标。最终监听范围可能受服务端 `GatewayPorts` 配置影响；应用不会自动修改该配置。

## 本地进程行为

应用只跟踪并停止自己启动的 SSH 进程。它不会扫描、接管或终止用户手动启动的 SSH 连接。

## 公开反馈时的隐私提醒

提交 issue、截图或日志前请脱敏：

- 真实 Host、内网 IP、公网 IP 和域名。
- 用户名、组织名和项目名。
- 私钥路径、证书路径、token 和密码。
- 完整 SSH 配置文件内容。

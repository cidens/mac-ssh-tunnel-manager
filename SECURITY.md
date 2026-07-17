# 安全政策

[English](SECURITY.en.md) | 中文

`ssh-tunnel-manager` 会启动系统 `/usr/bin/ssh` 并处理本地端口监听状态，因此安全问题请谨慎报告，避免在公开 issue 中贴出真实环境信息。

## 支持版本

当前只维护最新公开版本和 `main` 分支。旧版本没有长期安全维护承诺。

## 报告安全问题

仓库已经启用 GitHub Private Vulnerability Reporting。请通过以下私密入口报告安全问题，不要先创建公开 Issue：

- [新建私密漏洞报告](https://github.com/cidens/mac-ssh-tunnel-manager/security/advisories/new)

报告时请提供受影响版本、最小复现步骤、预期影响和已经完成的脱敏说明。如果私密入口暂时不可用，可以创建一个不含技术细节的脱敏 Issue，说明“私密安全报告入口不可用”，等待维护者处理。

- 可能导致任意命令执行的问题。
- 可能泄露 SSH Host、用户名、内网 IP、私钥路径或本地配置的问题。
- 可能错误终止非本应用启动的 SSH 进程的问题。
- 可能绕过输入校验并影响 SSH 参数生成的问题。

## 不要公开提交的信息

报告问题时请先脱敏：

- 真实 SSH Host 别名。
- 内网 IP、公网 IP 和域名。
- 用户名、组织名、项目名。
- 私钥路径、证书路径、token、密码。
- 完整的 `~/.ssh/config`。

可以使用这些占位值：

- `example-bastion`
- `example-service`
- `203.0.113.10`
- `127.0.0.1:18080`

## 响应预期

这是个人维护的小型工具，暂不承诺固定响应 SLA。确认问题后，优先处理会影响本地安全边界、进程管理和 SSH 参数生成的漏洞。

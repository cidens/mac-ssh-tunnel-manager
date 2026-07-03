# 贡献指南

[English](CONTRIBUTING.en.md) | 中文

欢迎提交 issue 和 pull request。这个项目目前保持小而清晰，优先保证 SSH 参数生成、安全边界、端口状态判断和 macOS 菜单栏体验稳定。

## 本地开发

环境要求：

- macOS 14 或更高版本。
- Xcode 26 或兼容的 Swift 6 工具链。

运行测试：

```bash
swift test
```

开发运行：

```bash
swift run ssh-tunnel-manager
```

打包本机应用：

```bash
./scripts/build-app-bundle.sh /private/tmp/SSH\ Tunnel\ Manager.app
```

## 提交前检查

提交前请至少运行：

```bash
swift test
git diff --check
```

如果改动影响打包、资源、本地化或 Info.plist，也请运行：

```bash
./scripts/build-app-bundle.sh /private/tmp/SSH\ Tunnel\ Manager.app
```

## 文档和示例脱敏

公开 issue、PR、文档和测试中不要包含真实信息：

- 真实 Host 别名、内网 IP、公网 IP、域名。
- 用户名、公司名、项目名。
- token、密码、私钥路径、证书路径。
- 完整的 `~/.ssh/config`。

示例请使用：

- `example-bastion`
- `example-service`
- `203.0.113.10`
- `127.0.0.1`
- `appuser`

## 代码约定

- 不通过 shell 字符串拼接启动 SSH，继续使用 `Process.arguments`。
- 新增用户可见文案时，同时更新 App/Core 的英文和简体中文 `.strings`。
- 不改变 `tunnels.json` 结构，除非同时补迁移说明和测试。
- 不自动编辑用户的 `~/.ssh/config`。
- 不终止非本应用启动并跟踪的 SSH 进程。

## Pull Request 建议

PR 描述建议包含：

- 变更目的。
- 主要实现点。
- 测试命令和结果。
- 是否涉及安全边界、SSH 参数、本地化或打包。

# 更新日志

[English](CHANGELOG.en.md) | 中文

本项目遵循语义化版本号的基本习惯：修复问题更新 patch，兼容新增功能更新 minor，破坏性变化更新 major。

## 0.2.1

- 对非回环本地监听地址增加明确风险确认，包括手动转发、动态 SOCKS 和 SSH Config 中的 `LocalForward`。
- 修复 SSH Config 校验未消费 stderr 管道可能导致阻塞或超时的问题。
- 增加非回环绑定确认、SSH Config 解析和相关本地化测试。

## 0.2.0

初始公开版本。

- 支持 macOS 菜单栏管理 SSH 本地端口转发。
- 支持动态 SOCKS 隧道。
- 支持复用 `~/.ssh/config` 中已有 `LocalForward` 的 SSH Config 模式。
- 支持英文和简体中文界面，默认跟随 macOS 系统语言。
- 使用本地 JSON 保存隧道配置，不保存服务器密码或私钥。
- 提供本机安装脚本和小范围 zip 分发脚本。
- 补充架构、分发、隐私、安全、贡献、发布和排障文档。

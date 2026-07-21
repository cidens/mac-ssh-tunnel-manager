# 文档索引

本目录集中记录 SSH Tunnel Manager 的用户说明、实现设计、功能验收和发布维护资料。项目首页只保留常用入口；需要追溯功能范围、实现依据或验收结果时，从本页进入。

## 用户文档

- [架构说明](architecture.md)：模块边界、配置模型、运行状态和安全边界。
- [分发说明](distribution.md)：构建、安装、签名和版本更新方式。
- [隐私说明](privacy.md)：本地数据、网络行为和公开反馈注意事项。
- [排障手册](troubleshooting.md)：常见启动、端口、健康检查和系统权限问题。

英文版用户文档：

- [架构说明（英文）](architecture.en.md)
- [分发说明（英文）](distribution.en.md)
- [隐私说明（英文）](privacy.en.md)
- [排障手册（英文）](troubleshooting.en.md)

## 功能追溯

下表将功能需求、实现依据和验收记录关联起来。没有独立设计文档的功能，以当前架构说明作为实现依据；GitHub Issue 保存原始需求和范围讨论。

| 功能 | 需求 | 实现依据 | 验收记录 |
| --- | --- | --- | --- |
| 全局快捷键备用入口 | [需求](requirements-global-shortcut.md) | [技术设计](design-global-shortcut.md) | [验收](validation-global-shortcut.md) |
| 隧道编辑器 | [需求](requirements-tunnel-editor.md) | [设计](design-tunnel-editor.md) | [验收](validation-tunnel-editor.md) |
| 标签、收藏、搜索和排序 | [Issue #2](https://github.com/cidens/mac-ssh-tunnel-manager/issues/2) | [架构说明](architecture.md) | [验收](validation-config-organization.md) |
| 连接通知与诊断 | [Issue #3](https://github.com/cidens/mac-ssh-tunnel-manager/issues/3) | [架构说明](architecture.md) | [验收](validation-connection-notifications.md) |
| SSH Config 只读导入 | [Issue #4](https://github.com/cidens/mac-ssh-tunnel-manager/issues/4) | [架构说明](architecture.md) | [验收](validation-ssh-config-import.md) |
| JSON 配置导入导出 | [Issue #6](https://github.com/cidens/mac-ssh-tunnel-manager/issues/6) | [架构说明](architecture.md) | [验收](validation-json-import-export.md) |
| 自动重连与网络、睡眠恢复 | [Issue #7](https://github.com/cidens/mac-ssh-tunnel-manager/issues/7) | [架构说明](architecture.md) | [验收](validation-auto-reconnect.md) |
| 登录项与逐连接自动启动 | [Issue #8](https://github.com/cidens/mac-ssh-tunnel-manager/issues/8) | [架构说明](architecture.md) | [验收](validation-login-auto-start.md) |
| 连接组与多规则转发 | [Issue #18](https://github.com/cidens/mac-ssh-tunnel-manager/issues/18) | [架构说明](architecture.md) | [验收](validation-connection-groups.md) |
| 标签批量启动与停止 | [Issue #21](https://github.com/cidens/mac-ssh-tunnel-manager/issues/21) | [架构说明](architecture.md) | [验收](validation-tag-batch-actions.md) |
| 规则级连接健康检查 | [Issue #22](https://github.com/cidens/mac-ssh-tunnel-manager/issues/22) | [架构说明](architecture.md) | [验收](validation-connection-health-check.md) |
| 本地监听端口推荐 | [Issue #23](https://github.com/cidens/mac-ssh-tunnel-manager/issues/23) | [架构说明](architecture.md) | [验收](validation-local-port-recommendation.md) |

## 发布与维护

- [发布流程](release.md)
- [发布流程（英文）](release.en.md)
- [0.5.0 发布前验收记录](validation-release-0.5.0.md)
- [中文更新日志](../CHANGELOG.md)
- [英文更新日志](../CHANGELOG.en.md)
- [贡献指南](../CONTRIBUTING.md)
- [安全政策](../SECURITY.md)
- [贡献者行为准则](../CODE_OF_CONDUCT.md)
- [许可证](../LICENSE)

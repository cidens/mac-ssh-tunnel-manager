# 0.5.0 发布前验收记录

## 范围

- 目标版本：`0.5.0`
- 比较基线：最近一个实际公开的 Release `v0.4.0`
- 功能范围：标签批量操作、已有标签建议、规则级连接健康检查、本地监听端口推荐
- 本文记录创建 `v0.5.0` 标签前完成的发布准备与本机验收，不代表标签或 GitHub Release 已经发布

## 文档审查

- 中英文更新日志已将原“未发布”内容归档到 `0.5.0`，并保留空的“未发布”章节。
- README、架构、分发、排障和三个功能验收文档与当前实现一致；历史验收记录中的旧版本号未被机械替换。
- 仓库没有受版本影响的截图资产。测试示例中的私网地址已替换为 RFC 5737 保留地址 `203.0.113.10`。
- `.DS_Store`、`.vscode/`、`.build/` 和 `dist/` 只存在于忽略目录，没有被 Git 跟踪；提交范围不包含配置、日志、备份或分发产物。

## 自动化测试与性能

执行 `swift test -c release`，267 项测试全部通过。最大规模性能测试覆盖 1000 个连接组、每组 10 个标签、每组最多 20 条规则、100 个批量成员及 10,000 个唯一标签；各项 P95 均低于门槛，标签详细结果见 `validation-config-organization.md`。

## 分发包校验

- `scripts/package-app.sh` 成功生成 `dist/SSH Tunnel Manager-0.5.0.zip`。
- `unzip -t` 通过，压缩包仅包含应用包、签名、可执行文件、`Info.plist` 和 App/Core 本地化资源。
- `CFBundleShortVersionString` 为 `0.5.0`，开发语言为 `en`，本地化包含 `en` 与 `zh-Hans`。
- 解压后的应用通过 `codesign --verify --deep --strict`。
- zip SHA-256：`530c48846a2be990af2aad2928ccd37d566aecf2552e4002a641ad9bef7daf54`。

## 安装与冒烟

- 使用 `scripts/install-app.sh` 覆盖安装到 `/Applications/SSH Tunnel Manager.app`。
- 安装版版本为 `0.5.0`，严格签名校验通过；安装版和已校验压缩包内可执行文件 SHA-256 均为 `964b4b0fa4a0ba4300850196e4494bee7d11750e0fdcfd09508c0341a7e1de91`。
- 通过绝对路径环境变量 `SSH_TUNNEL_MANAGER_APPLICATION_SUPPORT_DIRECTORY` 使用隔离目录启动安装版，并使用 3 个英文 SSH Config 示例覆盖重复与交叉标签。中英文界面的已有标签建议均完成人工验收，未发现文字截断或布局问题。
- 冒烟过程没有读取、修改或启动用户的真实隧道配置。

## GitHub Release 审核稿

标题：

```text
v0.5.0 · Tag Batch Actions, Health Checks, and Port Recommendations
```

正文：

```markdown
## Changes since v0.4.0

### Tag Batch Actions

- Tags now act as dynamic groups with status summaries and one-click batch start or stop across every matching connection, independent of search, favorites, and sorting.
- Batch starts preserve manual order, limit preflight concurrency to four, share one listener snapshot and index, and continue after individual skips or failures.
- Existing tags can be selected while editing; the main panel provides three replaceable pinned tags and a searchable picker with configuration counts. Each tag is limited to 16 characters.

### Connection Health Checks

- Added opt-in per-rule TCP and HTTP/HTTPS checks for Local Forward rules, plus SOCKS5 handshake checks for Dynamic Forward rules.
- Health remains separate from SSH process state: three consecutive failures mark a rule unhealthy, one success restores it, and health failures do not stop SSH or trigger reconnection.

### Local Port Recommendations

- Added explicit available-port recommendations for Local Forward and Dynamic SOCKS rules without changing drafts until the user accepts a result.
- Recommendations exclude configured and system listeners, preserve matching `openURL` paths and parameters when adopted, and keep save-time and start-time conflict checks authoritative.

### Reliability and Compatibility

- Added bounded probe and batch concurrency, cancellation and stale-result protection, shared listener snapshots, and maximum-scale performance coverage without blocking the main thread.
- Configuration export now uses `schemaVersion = 3` for optional health-check settings; schema v1 and v2 imports remain supported with health checks disabled by default.

### Distribution

- The zip remains ad-hoc signed and is not notarized with an Apple Developer ID.
- On first launch, macOS may require right-clicking the app and choosing Open, or allowing it in System Settings.

**Full Changelog:** [v0.4.0...v0.5.0](https://github.com/cidens/mac-ssh-tunnel-manager/compare/v0.4.0...v0.5.0)
```

## 结论

0.5.0 的发布文档、Release 测试、性能门槛、分发包、签名、版本、本地化、安装版一致性和隔离启动验收均通过，已有标签建议的中英文界面也已人工审核。相关变更可以进入 PR 审核；创建并推送 `v0.5.0` 标签仍需维护者另行确认。

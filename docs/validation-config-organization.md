# 配置组织功能验收记录

## 验收范围

本文记录 GitHub Issue #2“增加标签、收藏、搜索和排序”的实现验收。验收基于分支 `codex/issue-2-config-organization`，最终本地提交为 `88e664e`。

本次功能不改变 SSH 命令参数、隧道进程生命周期或已有配置的业务字段，只增加本地组织元数据和展示逻辑。

## 自动化验证

执行：

```bash
swift test
git diff --check
```

结果：

- 97 项 Swift 测试全部通过。
- 补丁空白与格式检查通过。
- 旧版 JSON 可在缺少 `tags`、`isFavorite`、`manualOrder` 和 `lastUsedAt` 时继续读取。
- 标签规范化会去除首尾空白、忽略大小写重复项，并在规范化后检查 10 个标签和 32 字符限制。
- 组织元数据可通过 JSON 完整往返保存。
- 不同配置中的大小写变体标签只生成一个筛选入口。
- SSH Config 模式搜索不会匹配未实际存在的占位端口。
- 手工上下移动后的数组顺序和 `manualOrder` 会同时写入磁盘。
- 注入写盘失败后，收藏状态和手工顺序均恢复到操作前状态。

## Release 构建与安装验证

使用仓库构建脚本生成 Release 模式应用：

```bash
./scripts/build-app-bundle.sh '/private/tmp/SSH Tunnel Manager-issue-2.app'
codesign --verify --deep --strict --verbose=2 \
  '/private/tmp/SSH Tunnel Manager-issue-2.app'
```

验证结果：

- `CFBundleShortVersionString` 和 `CFBundleVersion` 均为 `0.3.2`。
- 应用包含英文和简体中文 App/Core 本地化资源。
- 应用使用 ad-hoc 签名并通过严格签名校验。
- 构建产物已覆盖安装到 `/Applications/SSH Tunnel Manager.app` 并成功启动。
- 本地测试 ZIP 为 `/private/tmp/SSH Tunnel Manager-0.3.2-issue-2-local-test.zip`。
- 修复手工排序后的 ZIP SHA-256 为 `130b082a865d16f5ad83408af8a3f8f1541e1f7ca37da693093650806ed30573`。

该 ZIP 仅用于本机验收，不是公开 `v0.3.2` Release 资产，也不应上传覆盖已有版本。

## 手工验收结果

2026-07-18 在真实 macOS 桌面环境中安装 Release 构建并执行配置组织功能测试。

首次测试发现手工排序箭头点击后没有产生顺序变化。根因是数组完成交换后，保存前又按旧 `manualOrder` 排序，导致交换被立即撤销。修复方式为先按照交换后的数组顺序重建连续 `manualOrder`，再执行原子保存；同时增加成功移动和写盘失败回滚测试。

修复版重新构建、签名、覆盖安装并启动后，用户确认手工测试正常。最终确认范围包括：

- 手工排序箭头能够调整配置顺序。
- 新顺序写入本地配置，自动化测试确认重新加载后保持。
- 标签、收藏、搜索、组合筛选和四种排序入口可用。
- 长标签使用横向滚动，不遮挡结果数量和清除入口。

## 验收结论

Issue #2 的本地实现、自动化测试、Release 构建和桌面手工测试均已通过，可以进入推送分支、创建 Pull Request 和 CI 验证阶段。

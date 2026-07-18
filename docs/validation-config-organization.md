# 配置组织功能验收记录

## 验收范围

本文记录 GitHub Issue #2“增加标签、收藏、搜索和排序”在 2026-07-18 完成的最终验收。

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

## 手工验收结果

2026-07-18 在真实 macOS 桌面环境中安装 Release 构建并执行配置组织功能测试。

- 手工排序箭头能够调整配置顺序。
- 新顺序写入本地配置，自动化测试确认重新加载后保持。
- 标签、收藏、搜索、组合筛选和四种排序入口可用。
- 长标签使用横向滚动，不遮挡结果数量和清除入口。
- 隐藏并重新打开面板后，搜索框不会保留导致界面不可操作的焦点状态。
- 删除或风险确认出现时搜索框退出焦点；`Esc` 优先取消确认，没有确认层时退出搜索焦点。
- 搜索文本在面板隐藏后保留，并可通过“清除”入口重置筛选。

## 验收结论

Issue #2 的自动化测试、Release 构建和桌面手工测试均已通过，满足功能验收条件。

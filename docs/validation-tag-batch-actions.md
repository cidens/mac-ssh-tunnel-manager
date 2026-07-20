# 标签批量操作验收记录

## 范围

- Issue：#21
- 开发分支：`codex/issue-21-tag-batch-actions`
- 应用版本：`0.5.0` 开发测试包，不是公开 Release
- 数据模型：沿用现有标签，不增加场景模型、持久化字段或配置迁移

## 已实现功能

- 选中标签后显示全部成员数，以及运行、连接中或等待、失败和停止数量。
- 提供显式“全部启动”和“全部停止”操作，并在执行前说明范围是该标签的全部成员；搜索、收藏、排序和当前列表可见范围不会缩小批量范围。
- 标签匹配忽略大小写和变音符号，成员始终按持久化的手工顺序处理。
- 批量启动的预检最多并发 4 条；整个批次只建立一次所有者感知的应用内监听索引，并至多读取一次系统监听快照，启动请求按手工顺序提交。
- 已运行、没有启用规则、风险未确认、预检失败、操作期间被删除或被手工停止的连接会跳过并说明原因；单条失败不阻塞后续成员。
- 预检期间配置发生变化时按 UUID 重新读取并复检，避免使用旧草稿启动。
- 批量停止覆盖运行中、连接中、等待网络和等待重连状态，并取消尚未提交的批量启动请求；进程终止最多并发 4 条。
- 操作完成后汇总已请求启动或已停止、跳过和失败数量，并可展开查看成员级原因。启动结果不把“已提交进程”误写成“连接稳定成功”。
- 批量操作使用运行代次拒绝过期结果；父任务取消会传递给监听快照和 `ssh -G` 子进程；最近使用时间合并写盘，避免每启动一条都序列化全部配置。

## 失败边界

- 标签成员为空时返回空结果，不启动或停止任何进程。
- 重复点击批量启动不会创建第二个批次；批量停止可以抢占仍在执行的批量启动。
- 单条手工停止优先于尚未提交的批量启动，旧预检结果不能把它重新拉起。
- 停止进程失败只计入该成员失败，不影响其他成员终止。
- 批量操作不自动确认非回环监听风险，不绕过规则、SSH Config 或监听冲突校验。
- 批量操作不改变标签、搜索、收藏、排序、自动连接或自动重连配置。

## 自动化测试

自动化测试覆盖：

- `swift test` 共 231 项测试通过。
- 标签大小写不敏感匹配、手工顺序和四类状态数量守恒。
- 100 个任务保持输入顺序，实际并发不超过 4。
- 搜索与收藏筛选不影响标签全部成员，预检乱序完成时仍按手工顺序提交启动。
- 重复点击、单条跳过或失败、批量停止抢占、单条手工停止、成员删除和配置变化。
- 风险未确认、无启用规则、SSH Config 或本地监听冲突，以及每批一次系统监听快照。
- 所有者感知监听索引只排除当前连接自身，仍能识别其他连接的精确地址、`localhost` 和通配地址冲突；20000 条规则集中于同一端口时不会触发数组写时复制退化。
- 父任务取消会取消后台预检工作，已取消的后台结果不会回写当前批次。
- 中英文资源键一致，代表性批量操作文案均可本地化。

执行命令：

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/ssh-tunnel-manager-swift-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/ssh-tunnel-manager-swift-cache \
  swift test --disable-sandbox
```

## 性能验收

### 方法

- 使用 Release 构建和注入式假预检器、假启动器，不包含真实 SSH、认证或公网延迟。
- 每项预热 5 次，正式执行 30 次，记录中位数和 P95，以 P95 作为通过标准。
- 聚合测试使用 1000 个连接组、每组 10 个标签；监听索引测试使用 1000 个连接组、每组 20 条规则，并连续查询 100 个成员；批量测试使用 100 个标签成员。
- 主线程测试注入每次等待 75 ms 的慢预检器；若预检错误地在主线程执行，指标会超过 50 ms 门槛。

测试环境：

- 机型：MacBook Pro（Mac14,7）
- 芯片：Apple M2，8 核
- 内存：16 GB
- 系统：macOS 26.5（25F71）
- 应用版本：0.5.0 开发构建
- 测试日期：2026-07-20

执行命令：

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/ssh-tunnel-manager-swift-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/ssh-tunnel-manager-swift-cache \
  swift test -c release --disable-sandbox \
  --filter 'largeTagGroupAggregationMeetsReleasePerformanceBudget|oneHundredMemberSchedulerMeetsReleasePerformanceBudget|largeSystemTagBatchPreflightMeetsReleasePerformanceBudget|maximumSamePortListenerIndexAvoidsCopyOnWriteRegression|oneHundredMemberBatchRequestMeetsReleasePerformanceBudget|slowTagBatchPreflightDoesNotBlockTheMainActor|boundedTagBatchSchedulerPreservesOrderAndNeverExceedsFourTasks|detachedTagBatchWorkPropagatesParentCancellation'
```

| 指标 | 中位数 | P95 | 门槛 | 结果 |
| --- | ---: | ---: | ---: | --- |
| 1000 个连接组、每组 10 个标签的匹配与状态汇总 | 6.507 ms | 8.980 ms | 100 ms | 通过 |
| 20000 条监听规则建立索引并查询 100 个成员 | 66.345 ms | 75.046 ms | 100 ms | 通过 |
| 20000 条规则集中在同一端口时建立索引 | 15.991 ms | 21.494 ms | 100 ms | 通过 |
| 100 个成员的纯调度 | 0.145 ms | 0.237 ms | 200 ms | 通过 |
| 100 个成员的假预检与批量请求 | 11.491 ms | 13.124 ms | 200 ms | 通过 |
| 注入 75 ms 慢预检时的主线程响应 | 6.326 ms | 6.478 ms | 50 ms | 通过 |
| 批量任务最大并发数 | 4 | 4 | 不超过 4 | 通过 |

一次刷新只构建一个标签快照，不按状态或标签重复扫描完整集合。外部网络、SSH 认证和目标服务响应不进入上述计时。

## 性能与内存安全审查

- 已修正预检最初按成员重复重建“其他连接监听集合”的实现。当前每个批次只扫描一次最多 20000 条规则，后续成员按端口查询共享索引，避免接近 `成员数 × 全部规则数` 的时间和临时内存增长。
- 索引中的每条启用监听只保存一次所有者 UUID 和规范化 Host；常见的单监听端口使用内联首条记录，同端口确有更多监听时才创建附加数组。索引、成员引用、预检结果和最终汇总均受 1000 个连接组及每组 20 条规则的仓库上限约束。
- 标签列表改为逐连接遍历，不再通过 `flatMap` 分配最多 10000 项的中间标签数组；结果详情在一次 SwiftUI 渲染中只生成一次跳过或失败列表。
- 批量任务闭包弱引用 `TunnelManager`，并发任务最多为 4；批量结果只保留最近一次且不保存历史队列。应用终止、批量停止或新代次会取消旧任务，取消继续传递到真实 `lsof` 和 `ssh -G` 等待逻辑。
- `manualStopVersions` 只为发生停止的连接保存一个计数；删除成功后同步移除 UUID。若删除写盘失败，连接会恢复，因此保留计数以继续阻止旧批次将其拉起。
- 本轮未发现越界访问、无上限任务创建、结果历史累积或永久强引用环。系统进程、网络超时和 SSH 认证时间仍不计入纯逻辑性能，但已确认等待不在主线程执行。

## 发布配置构建验证

执行：

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/ssh-tunnel-manager-swift-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/ssh-tunnel-manager-swift-cache \
  ./scripts/build-app-bundle.sh '/private/tmp/SSH Tunnel Manager-tag-batch-review.app'
```

结果：

- Release 构建成功，`CFBundleShortVersionString` 为 `0.5.0`。
- `codesign --verify --deep --strict` 通过。
- `CFBundleDevelopmentRegion` 为 `en`，`CFBundleLocalizations` 包含 `en` 与 `zh-Hans`。
- App 与 Core 的英文、简体中文资源包均存在，发布包内包含标签批量操作文案。
- 最终审查构建已覆盖安装到 `/Applications/SSH Tunnel Manager.app`；安装版与 `/private/tmp` 审查包的可执行文件 SHA-256 一致。安装后未自动启动，避免触发真实配置中的自动连接。

## 隔离实机验收

本轮首次尝试使用 `CFFIXED_USER_HOME` 隔离配置，但 macOS 26.5 的 `FileManager` 仍返回真实应用支持目录。测试应用只读显示配置且没有启动连接或执行批量操作，随即终止；真实 `tunnels.json` 前后 SHA-256 一致。为避免形成伪隔离，应用增加仅在显式设置绝对路径时生效的 `SSH_TUNNEL_MANAGER_APPLICATION_SUPPORT_DIRECTORY`，统一覆盖配置、快捷键和通知设置目录；相对路径或空值不会生效，普通启动行为不变。

一次通过全局快捷键重新显示面板时，macOS 又启动了同 Bundle ID 的已安装应用，辅助功能查询因此命中正式实例。两个实例均未启动连接或执行批量操作，并在发现后立即终止；后续验收只在发布包初始显示窗口中按隔离 PID 操作，不再使用全局快捷键。实机结果：

1. 通过：显式隔离目录只加载 6 条脱敏配置，标题显示“运行 0 · 异常 0 · 总数 6”，没有读取真实连接列表。
2. 通过：选中“生产”标签后，列表和动态分组均为 5 条；状态汇总为运行 0、连接中或等待 0、失败 0、停止 5。
3. 通过：开启“仅收藏”后列表只显示 2 条，动态分组仍显示 5 条；按钮帮助明确说明搜索、收藏和排序不改变操作范围。
4. 通过：“全部启动”确认框说明将处理全部 5 个成员，并跳过风险未确认或预检失败项。5 条虚构 SSH Config 引用只执行本地 `ssh -G` 预检，结果为“启动请求 0 · 已跳过 5 · 失败 0”，没有发起 SSH 连接。
5. 通过：“全部停止”确认框覆盖连接中、等待网络和等待重连；5 条已停止成员汇总为“已停止 0 · 已跳过 5 · 失败 0”。
6. 通过：跳过和失败详情默认折叠，展开内容限制在独立滚动区域，不会把主列表和底部操作挤出面板。
7. 通过：英文界面显示 `5 total · 0 running · 0 connecting/waiting · 0 failed · 5 stopped`，两个按钮帮助文本完整且范围一致；中英文资源测试同时通过。
8. 通过：验收结束后没有测试应用或测试 SSH 进程残留；真实 `tunnels.json` 的 SHA-256 与验收前一致。

## 回滚

此功能没有配置迁移。回滚代码或安装旧版本即可；现有 `tunnels.json` 无需恢复或转换。

## 当前结论

Issue #21 的标签动态分组、状态汇总、筛选无关范围、稳定手工顺序、4 路并发上限、单条失败隔离、停止抢占、取消传播、过期结果拒绝、最大规模预检索引、双语界面、性能门槛、发布配置应用包和显式隔离实机验收均已通过。性能与内存安全复核发现的重复全量扫描、后台子任务取消和删除后代次清理问题已经修正，没有剩余阻断项。

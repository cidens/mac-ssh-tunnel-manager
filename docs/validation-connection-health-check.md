# 规则级连接健康检查验收记录

## 结论

Issue #22 已通过功能、协议、取消与过期结果、配置迁移、双语资源、性能、内存安全、发布构建和实机界面验收，可以进入 PR 审查与合并。

## 范围

- 分支：`codex/issue-22-connection-health-check`
- 版本：`0.5.0` 开发测试包
- 支持：本地转发 TCP、HTTP/HTTPS；动态 SOCKS 的 SOCKS5 握手
- 暂不支持：远程转发和 SSH Config 引用的端到端检查

健康检查默认关闭，状态与 SSH 进程、通知和自动重连相互独立。默认间隔 30 秒、超时 3 秒；连续失败 3 次标记异常，成功 1 次恢复。全局最多 8 条并发，停止、编辑、删除、重启、断网、睡眠和退出会取消或暂停任务，并以运行代次拒绝过期结果。

配置导出升级为 `schemaVersion = 3`。v1、v2 继续可读，但迁移时强制关闭健康检查；导入预览不启动探测。

## 自动化与内存安全

```bash
# Debug 全量
env CLANG_MODULE_CACHE_PATH=/private/tmp/ssh-tunnel-manager-health-debug-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/ssh-tunnel-manager-health-debug-cache \
  swift test --disable-sandbox

# Release 全量
env CLANG_MODULE_CACHE_PATH=/private/tmp/ssh-tunnel-manager-health-release-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/ssh-tunnel-manager-health-release-cache \
  swift test -c release --disable-sandbox

# 探测器与调度器内存安全
env CLANG_MODULE_CACHE_PATH=/private/tmp/ssh-tunnel-manager-health-asan-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/ssh-tunnel-manager-health-asan-cache \
  swift test --disable-sandbox --sanitize=address \
  --filter 'SystemHealthProberTests|HealthCheckSchedulerTests'
```

- Debug、Release：各 243 项测试通过。
- AddressSanitizer：21 项重点测试通过，无内存错误。
- 覆盖 TCP、HTTP/HTTPS、SOCKS5、失败分类、3 次失败阈值、单次成功恢复、8 并发、取消、排队、旧结果隔离、模式切换、JSON 迁移和双语资源。

## 性能验收

环境：MacBook Pro（Mac14,7）、Apple M2、macOS 26.5（25F71）、应用 0.5.0。

短性能项目使用 Release 构建和注入式假探测器，预热 5 次、正式执行 30 次，以 P95 判定。网络、SSH 和目标服务延迟不计入本地算法耗时。

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/ssh-tunnel-manager-health-release-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/ssh-tunnel-manager-health-release-cache \
  swift test -c release --disable-sandbox \
  --filter 'oneHundredDueHealthChecksMeetReleaseSchedulingBudget|aggregatingMaximumDisabledHealthCheckDataStaysWithinBudget|probeWorkDoesNotContinuouslyBlockTheMainThread'
```

| 指标 | 中位数 | P95 | 门槛 | 结果 |
| --- | ---: | ---: | ---: | --- |
| 100 条同时到期检查完成调度 | 9.908 ms | 15.915 ms | 1,000 ms | 通过 |
| 1000 组 × 20 条关闭规则聚合 | 4.479 ms | 5.702 ms | 100 ms | 通过 |
| 注入 75 ms 慢探测时主线程响应 | 0.110 ms | 0.441 ms | 50 ms | 通过 |

10 分钟资源测试使用 100 条检查、30 秒间隔和即时响应假探测器：

```bash
env SSH_TUNNEL_MANAGER_LONG_PERFORMANCE=1 \
  SSH_TUNNEL_MANAGER_PERFORMANCE_SECONDS=600 \
  CLANG_MODULE_CACHE_PATH=/private/tmp/ssh-tunnel-manager-health-release-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/ssh-tunnel-manager-health-release-cache \
  swift test -c release --disable-sandbox \
  --filter longRunningHealthChecksStayWithinCPUAndMemoryBudgets
```

| 指标 | 实测 | 门槛 | 结果 |
| --- | ---: | ---: | --- |
| 600.9 秒内完成次数 | 2000 次 | 不少于 100 次 | 通过 |
| 平均 CPU | 0.089% | 2% | 通过 |
| 额外峰值常驻内存 | 0.766 MiB | 20 MiB | 通过 |

## 发布构建与实机验收

- 构建并安装签名有效的 `0.5.0` 应用；版本、中英文资源和 `codesign --verify --deep --strict` 均通过。
- 真实 OpenSSH 本地转发和动态 SOCKS 隧道中，TCP、HTTP `200` 和 SOCKS5 无认证握手通过。
- 临时服务连续返回 3 次 HTTP `404` 后进入异常；恢复 HTTP `200` 后，下一次检查立即恢复健康。
- 取消、槽位释放、运行代次隔离、断网与睡眠暂停、关闭检查不创建任务和 8 并发限制通过。
- 本地、远程、动态 SOCKS、SSH Config 表单约束及健康参数、端点校验通过。
- 用户人工检查中英文界面、状态徽标、帮助文字和编辑 Sheet，未发现视觉截断或布局问题。
- 验收后已删除临时服务和配置、关闭临时端口，并恢复测试前运行的连接。

验收日期：2026-07-21。结果：全部通过。

## 回滚

旧版应用可忽略本地 `tunnels.json` 中未知的 `healthCheck` 字段，但健康检查不会生效。v3 导出文件不能由只支持 v2 的旧版导入器读取；回滚前应保留原配置或导出文件，并使用 0.5.0 或更高版本处理 v3 文件。

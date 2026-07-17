# mac-ssh-tunnel-manager 架构说明

[English](architecture.en.md) | 中文

## 项目定位

`mac-ssh-tunnel-manager` 是公开仓库名。应用名称为 `SSH Tunnel Manager`，SwiftPM executable target 为 `ssh-tunnel-manager`。它是一个个人使用的 macOS 菜单栏应用，用 GUI 管理 SSH 本地端口转发和动态 SOCKS 隧道。应用不实现 SSH 协议，也不保存服务器密码或私钥，而是直接调用系统 `/usr/bin/ssh`，复用用户已有的 `~/.ssh/config`、ssh-agent 和 macOS Keychain。

当前版本为 `0.3.1`，版本号定义在 `SSHTunnelCore/AppVersion.swift`。

## 模块结构

项目使用 SwiftPM 管理。运行代码分为两个 target：

- `SSHTunnelCore`：纯逻辑层，负责隧道和全局快捷键设置模型、JSON 读写、SSH 参数生成、输入校验、端口监听解析、stderr 缓冲、进程终止等待、状态统计和版本号。
- `SSHTunnelManagerApp`：macOS AppKit 与 SwiftUI 菜单栏应用，负责状态栏项目、主界面展示、全局快捷键注册、表单、列表、按钮、状态展示，以及启动/停止系统 SSH 进程。

两个运行 target 都包含本地化资源。当前支持英文 `en` 和简体中文 `zh-Hans`，`Package.swift` 的 `defaultLocalization` 为 `en`。应用不提供内部语言切换，运行时跟随 macOS 系统语言；测试可以通过字符串封装显式指定语言。

测试代码分为两个 test target：

- `SSHTunnelCoreTests`：覆盖核心模型、命令生成、校验、端口解析、状态判定和配置读写。
- `SSHTunnelManagerAppTests`：覆盖 App 层可抽离的表单显示策略，避免 SwiftUI 条件分支和隧道模式不一致。

主要文件职责：

- `TunnelConfig.swift`：定义隧道配置、三种模式和校验错误。
- `CoreStrings.swift`：Core 层本地化入口，负责状态摘要、运行状态和校验错误文案。
- `SSHCommandBuilder.swift`：根据配置生成固定 SSH 参数，不经过 shell 字符串拼接。
- `TunnelConfigStore.swift`：把隧道配置读写到本机 JSON 文件。
- `GlobalShortcutSettings.swift`：定义全局快捷键、修饰键、默认组合和设置校验。
- `GlobalShortcutSettingsStore.swift`：把快捷键设置原子写入独立 JSON 文件。
- `PortStatusParser.swift`：解析 `lsof` 输出，判断本地端口是否监听。
- `SSHConfigOutputParser.swift`：解析 `ssh -G` 输出，确认 SSH Config 模式包含 `LocalForward`。
- `ManagedProcessTerminator.swift`：终止应用自己启动的进程，并在短超时内等待退出。
- `TunnelSummary.swift`：汇总运行中、异常和总隧道数量。
- `TunnelManager.swift`：管理配置列表、运行时状态、SSH `Process` 生命周期和保存前校验。
- `AppDelegate.swift`：组装单一 `TunnelManager`、菜单展示和全局快捷键生命周期。
- `MenuPresentationCoordinator.swift`：创建状态栏项目和可编程控制的主界面面板。
- `GlobalShortcutSystem.swift`：封装 macOS 快捷键注册、注销、事件回调和系统快捷键查询。
- `GlobalShortcutController.swift`：管理启动恢复、录制状态、冲突分类和保存回滚事务。
- `GlobalShortcutSettingsView.swift`、`ShortcutRecorderView.swift`：提供快捷键设置和聚焦录制界面。
- `AppStrings.swift`：App 层本地化入口，负责菜单、按钮、表单、提示和应用生成的错误文案。
- `TunnelMenuView.swift`：菜单栏窗口 UI，包括添加、编辑、启动、停止、打开 URL 和删除。
- `TunnelModeFormFields.swift`：集中定义不同隧道模式在表单中应显示的字段。
- `scripts/build-app-bundle.sh`：把 SwiftPM release 构建打包成 `.app`，写入 `Info.plist` 并做本机 ad-hoc 签名。
- `scripts/install-app.sh`：复用 `.app` 构建脚本，安装到 `/Applications`。
- `scripts/package-app.sh`：复用 `.app` 构建脚本，生成可分发的 zip 包到 `dist/`。

## 安装方式

开发调试时可以直接运行：

```bash
swift run ssh-tunnel-manager
```

日常使用推荐安装成 macOS 应用：

```bash
./scripts/install-app.sh
```

安装脚本会完成以下步骤：

1. 执行 `swift build -c release --product ssh-tunnel-manager`。
2. 创建临时的 `SSH Tunnel Manager.app` 目录结构。
3. 把 SwiftPM 生成的本地化 resource bundle 复制到 `.app/Contents/Resources`。
4. 从 `AppVersion.swift` 读取当前版本号，写入 `Info.plist`。
5. 声明 `CFBundleDevelopmentRegion=en` 和 `CFBundleLocalizations=en, zh-Hans`。
6. 设置 `LSUIElement=true`，让应用以菜单栏工具方式运行，不显示 Dock 图标。
7. 使用 `codesign --sign -` 做本机 ad-hoc 签名。
8. 安装到 `/Applications/SSH Tunnel Manager.app`。

安装脚本可以重复运行。代码更新后再次执行，会重新构建并覆盖安装应用。隧道配置文件保存在用户目录的 Application Support 中，不会被覆盖安装删除。

小范围分发给别人使用时，可以运行：

```bash
./scripts/package-app.sh
```

脚本会生成：

```text
dist/SSH Tunnel Manager-0.3.1.zip
```

zip 包使用本机 ad-hoc 签名，不包含 Apple Developer ID notarization，适合可信用户小范围分发。正式公开分发需要后续接入 Developer ID 签名和 notarization。

## 配置模型

配置保存在：

```text
~/Library/Application Support/ssh-tunnel-manager/tunnels.json
```

每条隧道使用 `TunnelConfig` 表示，核心字段包括：

- `id`：隧道唯一标识。
- `mode`：`localForward`、`dynamicForward` 或 `sshConfig`。
- `name`：界面显示名称。
- `openURL`：可选的本地访问 URL。
- `sshHost`、`localHost`、`localPort`、`remoteHost`、`remotePort`：手动转发模式使用。
- `sshHost`、`localHost`、`localPort`：动态 SOCKS 模式使用。
- `sshConfigName`：SSH Config 模式使用。

旧版 JSON 没有 `mode` 字段时，默认按 `localForward` 解码，保证已有配置可继续读取。

全局快捷键设置与隧道配置分离，保存在：

```text
~/Library/Application Support/ssh-tunnel-manager/settings.json
```

字段包括设置版本、是否启用、物理键码和修饰键集合。文件不存在时使用默认 `⌃⌥⌘T` 并启用；异常文件不会自动覆盖，应用使用默认值运行并在设置界面提示。两个配置文件都使用原子写入，目录权限为 `0700`，文件权限为 `0600`。

## 菜单展示与全局快捷键

应用继续设置 `LSUIElement=true`，不显示 Dock 图标。展示层不再依赖无法编程式打开的 SwiftUI `MenuBarExtra`，改为：

- `NSStatusItem` 提供方形纯图标和点击入口；动态名称与运行数量通过悬浮提示和辅助功能标签展示。
- 单一 `NSPanel` 使用 `NSHostingController` 承载现有 `TunnelMenuView`。
- 面板标题和底部“添加隧道/退出”操作固定，只有中间隧道列表随内容滚动。
- 菜单栏点击保持打开或关闭行为。
- 全局快捷键切换主界面的显示或关闭；应用重新打开请求仍始终展示、置前和聚焦主界面。
- 外部请求按鼠标所在显示器定位；已经显示的面板不会重复创建。
- `TunnelMenuView`、状态栏入口和快捷键入口共享同一个 `TunnelManager`。

默认全局快捷键为 `⌃⌥⌘T`。系统实现分为两层：

1. `CopySymbolicHotKeys` 检查当前已启用的 macOS 系统级快捷键。
2. `RegisterEventHotKey` 使用独占选项试注册候选组合，明确的占用结果归类为冲突。

macOS 不能完整枚举第三方应用内部或非独占快捷键，因此界面不会宣称能够检测全部冲突，也不会猜测占用方名称。全局注册不使用键盘事件监听，不要求辅助功能或输入监控权限。

修改快捷键时，控制器先保留旧注册，再注册不可分发的候选组合。候选注册成功后原子写入 `settings.json`，写入成功才提升候选令牌并注销旧令牌。任一步骤失败都会注销候选令牌并保留原快捷键。

## 三种隧道模式

### 手动转发模式

手动转发模式由应用字段生成完整 `-L` 参数：

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -L localHost:localPort:remoteHost:remotePort \
  sshHost
```

保存前会校验字段格式和本地端口是否已被占用。启动前也会再次检查本地端口，避免误覆盖用户手动打开的服务。

### 动态 SOCKS 模式

动态 SOCKS 模式由应用字段生成完整 `-D` 参数：

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -D localHost:localPort \
  sshHost
```

该模式不会声明固定远端目标，连接目标由使用 SOCKS 代理的客户端决定。保存前会校验 SSH Host、本地 bind host 和端口，保存和启动前都会检查本地端口是否已被占用。非回环本地 bind host 会在保存或启动前触发风险确认，避免用户无意中暴露 SOCKS 监听。

脱敏配置示例：

```text
名称：Example SOCKS
SSH Host：example-bastion
SOCKS：127.0.0.1 1080
打开 URL：留空
```

启动后，应用只负责保持本地 SOCKS 监听。需要走代理的命令仍要自行指定代理环境变量或应用代理配置，例如：

```bash
ALL_PROXY=socks5h://127.0.0.1:1080 git fetch
```

### SSH Config 模式

SSH Config 模式只保存 `sshConfigName`，由 `~/.ssh/config` 中的 Host 条目负责声明 `LocalForward`：

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  sshConfigName
```

保存和启动前都会运行：

```bash
ssh -G sshConfigName
```

应用会解析输出，要求至少存在一条 `localforward`，并检查其本地绑定地址。非回环绑定会在保存或启动前触发风险确认。`ssh -G` 校验有 10 秒超时，避免带 `Match exec`、`ProxyJump` 或慢 DNS 的配置被过早误判。

## 运行时状态

应用只管理自己启动的 SSH 进程，不会查找或终止用户手动打开的 SSH。

运行时状态由 `TunnelRuntimeState` 维护：

- `process`：应用启动的 SSH `Process`。
- `isPortListening`：手动转发和动态 SOCKS 模式下本地端口是否监听。
- `lastError`：最近一次错误。
- `stderrTail`：SSH stderr 最近几行。

状态展示由 `TunnelRuntimeStatusResolver` 决定：

- `Stopped`：没有进程、没有监听、没有错误。
- `Running`：应用启动的进程仍在运行，但需要检查本地端口的模式尚未确认监听。
- `Listening`：手动转发或动态 SOCKS 模式下应用进程运行，且本地端口已监听。
- `Port occupied`：没有应用进程，但本地端口已被其他进程占用。
- `Failed`：进程退出后留下错误信息。

SSH Config 模式不解析具体端口，因此运行中按应用进程状态显示 `Running`；如果 SSH 因 `LocalForward` 失败退出，stderr 会显示在隧道卡片中。

菜单栏窗口顶部会显示简短统计：

```text
运行 X · 异常 Y · 总数 Z
```

其中 `Running` 和 `Listening` 计入运行中，`Failed` 和 `Port occupied` 计入异常。

## 退出与进程清理

应用底部提供“退出”按钮。退出前会先关闭当前应用自己启动并记录的 SSH 进程，然后再退出程序。

为避免只覆盖按钮路径，`TunnelManager` 同时监听 `NSApplication.willTerminateNotification`。因此通过系统正常退出路径关闭应用时，也会触发同一套清理逻辑。

清理时应用会先发送正常终止信号并短暂等待进程退出；在应用退出路径中，如果超时仍未结束，会对自己管理的进程做强制兜底。应用不会查找或终止用户手动打开的 SSH 连接，也不会自动清理历史残留的孤儿 SSH 进程。

## 输入与安全边界

应用不允许输入任意 shell 命令。所有启动参数都作为 `Process.arguments` 数组传入 `/usr/bin/ssh`。

校验策略：

- `sshHost` 和 `sshConfigName` 不能为空，不能包含空白、控制字符、明显 shell 元字符，也不能以 `-` 开头，避免被 OpenSSH 当作选项。
- 手动转发端点和动态 SOCKS bind host 不允许裸 IPv6，IPv6 必须使用 `[::1]` 形式。
- 本地 bind host 仍允许精确 `*` 以兼容需要局域网访问的场景，但非回环绑定在保存或启动前必须经过明确确认；远端 host 不允许通配符。
- `127.0.0.1`、`localhost`、`::1` 和 `[::1]` 按回环地址处理；其他本地绑定地址都按可能暴露处理，不进行 DNS 解析。
- SSH Config 模式会检查 `ssh -G` 解析出的 `LocalForward` 本地绑定地址，并使用相同的风险确认。
- `openURL` 只允许带 host 的 `http` 或 `https` URL。
- 端口必须在 `1...65535` 范围内。

## 错误处理

启动 SSH 时，应用持续读取 stderr，并用 `StderrTailBuffer` 保留最近几行。常见错误包括：

- 本地端口被占用。
- SSH Host 不存在。
- 认证失败或需要扫码登录。
- SSH Config 模式没有 `LocalForward`。
- `ExitOnForwardFailure=yes` 导致转发失败后 SSH 直接退出。

错误会显示在对应隧道卡片下方，方便用户定位问题。

## 测试策略

`Tests/SSHTunnelCoreTests` 覆盖纯逻辑层：

- JSON 配置读写和旧配置兼容。
- 全局快捷键默认值、有效性校验、稳定编码、配置版本和文件权限。
- 手动转发、动态 SOCKS 和 SSH Config 三种命令生成。
- Host、端口、URL 校验。
- `ssh -G` 输出中的 `localforward` 解析。
- `lsof` 输出中的监听端口解析。
- 运行时状态判定。
- 运行状态、状态摘要和校验错误的中英文展示。
- 托管进程终止等待。
- 隧道统计汇总。
- stderr 最近行缓存。
- 应用版本号。

`Tests/SSHTunnelManagerAppTests` 覆盖 App 层中可抽离的逻辑：

- 手动转发模式显示 SSH Host、本地和远端字段，不显示 SSH Config 字段。
- 动态 SOCKS 模式只显示 SSH Host 和 SOCKS 本地监听字段，不显示远端或 SSH Config 字段。
- SSH Config 模式只显示配置别名字段。
- App 层代表性 UI 文案和运行时错误的中英文展示。
- App 层和 Core 层英文、简体中文 `.strings` key 集合一致性。
- 快捷键启动注册、系统冲突、保存提交、持久化失败回滚、停用失败恢复和无修改重试。
- 录制当前活动快捷键时不触发主界面展示。

SwiftUI 视图渲染和系统 `Process` 生命周期主要通过编译、核心测试和手动验收验证。

## 手动验收

推荐验收路径：

1. 运行 `swift run ssh-tunnel-manager`。
2. 首次启动确认列表为空，显示“还没有隧道配置”。
3. 添加手动转发隧道，确认保存前会拦截本地端口占用。
4. 启动手动转发隧道，确认状态从 `Running` 变为 `Listening`。
5. 添加动态 SOCKS 隧道，使用脱敏 Host 示例值替换为自己的 SSH Host，确认启动后本地 SOCKS 端口进入 `Listening`。
6. 停止隧道，确认应用只停止自己启动的 SSH 进程。
7. 添加 SSH Config 模式隧道，确认配置名不存在或没有 `LocalForward` 时保存失败。
8. 配置有效 SSH Config 后启动，确认可打开 `openURL`。
9. 修改配置，确认 JSON 文件随之更新；点击删除后先取消，确认配置保留，再次删除并确认后检查配置已从 JSON 文件移除。
10. 分别在英文和简体中文系统语言下启动应用，确认菜单、表单、按钮、状态摘要和应用内错误提示跟随系统语言。
11. 隐藏菜单栏图标后按 `⌃⌥⌘T`，确认主界面显示并置前；再次按键确认主界面关闭。
12. 自定义快捷键并重启应用，确认新组合恢复、旧组合失效。
13. 使用测试辅助进程占用候选组合，确认冲突阻止保存且旧组合继续有效。
14. 在外接显示器和全屏空间中触发快捷键，确认面板位于当前交互屏幕。
15. 确认系统没有请求辅助功能或输入监控权限。

## 当前边界

当前版本刻意保持简单：

- 只支持 macOS。
- 只支持本地端口转发、动态 SOCKS 转发和 SSH Config 中已有的 `LocalForward`。
- 不自动编辑 `~/.ssh/config`。
- 不做登录项自启动。
- 不做自动重连。
- 不做远程转发。

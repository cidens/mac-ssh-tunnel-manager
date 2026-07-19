# mac-ssh-tunnel-manager 架构说明

[English](architecture.en.md) | 中文

## 项目定位

`mac-ssh-tunnel-manager` 是公开仓库名。应用名称为 `SSH Tunnel Manager`，SwiftPM executable target 为 `ssh-tunnel-manager`。它是一个个人使用的 macOS 菜单栏应用，用 GUI 管理 SSH 本地端口转发、远程端口转发和动态 SOCKS 隧道。应用不实现 SSH 协议，也不保存服务器密码或私钥，而是直接调用系统 `/usr/bin/ssh`，复用用户已有的 `~/.ssh/config`、ssh-agent 和 macOS Keychain。

当前版本为 `0.4.0`，版本号定义在 `SSHTunnelCore/AppVersion.swift`。

## 模块结构

项目使用 SwiftPM 管理。运行代码分为两个 target：

- `SSHTunnelCore`：纯逻辑层，负责隧道、自动连接和全局快捷键设置模型、JSON 读写、SSH 参数生成、输入校验、端口监听解析、stderr 缓冲、进程终止等待、状态统计和版本号。
- `SSHTunnelManagerApp`：macOS AppKit 与 SwiftUI 菜单栏应用，负责状态栏项目、主界面展示、全局快捷键注册、表单、列表、按钮、状态展示，以及启动/停止系统 SSH 进程。

两个运行 target 都包含本地化资源。当前支持英文 `en` 和简体中文 `zh-Hans`，`Package.swift` 的 `defaultLocalization` 为 `en`。应用不提供内部语言切换，运行时跟随 macOS 系统语言；测试可以通过字符串封装显式指定语言。

测试代码分为两个 test target：

- `SSHTunnelCoreTests`：覆盖核心模型、命令生成、校验、端口解析、状态判定和配置读写。
- `SSHTunnelManagerAppTests`：覆盖 App 层可抽离的表单显示策略，避免 SwiftUI 条件分支和隧道模式不一致。

主要文件职责：

- `TunnelConfig.swift`：定义隧道配置、四种模式、标签/收藏/顺序元数据和校验错误。
- `CoreStrings.swift`：Core 层本地化入口，负责状态摘要、运行状态和校验错误文案。
- `SSHCommandBuilder.swift`：根据配置生成固定 SSH 参数，不经过 shell 字符串拼接。
- `TunnelConfigStore.swift`：把隧道配置读写到本机 JSON 文件。
- `TunnelConfigurationTransfer.swift`：定义带版本的导出文档、导入限制、字段校验、监听冲突检查和相同 ID 合并策略。
- `TunnelRecoveryPolicy.swift`：定义连接生命周期、停止原因、运行代次、退避策略和 SSH 故障分类。
- `TunnelDiagnosticSanitizer.swift`：在保存或展示诊断前替换 SSH Host、非回环目标和用户主目录。
- `TunnelDiagnostics.swift`：定义稳定错误类别、通知周期去重状态和不含配置端点的结构化诊断报告。
- `ConnectionNotificationSettings.swift`：定义默认关闭的通知设置及独立原子存储。
- `GlobalShortcutSettings.swift`：定义全局快捷键、修饰键、默认组合和设置校验。
- `GlobalShortcutSettingsStore.swift`：把快捷键设置原子写入独立 JSON 文件。
- `PortStatusParser.swift`：解析 `lsof` 输出，判断本地端口是否监听。
- `SSHConfigDiscovery.swift`：只读遍历 `~/.ssh/config` 与可访问的 `Include`，发现明确 Host、检测循环和 `Match exec`。
- `SSHConfigOutputParser.swift`：解析 `ssh -G` 输出中的本地、远程和动态转发及监听范围。
- `ManagedProcessTerminator.swift`：终止应用自己启动的进程，并在短超时内等待退出。
- `TunnelSummary.swift`：汇总运行中、异常和总隧道数量。
- `TunnelManager.swift`：管理配置列表、筛选排序、运行时状态、SSH `Process` 生命周期和保存前校验。
- `SystemRecoveryMonitor.swift`：通过 `NWPathMonitor` 和 `NSWorkspace` 通知桥接网络、睡眠与唤醒事件。
- `ConnectionNotificationController.swift`：只在用户启用时请求通知权限，并隔离权限、投递和设置失败，不影响隧道生命周期。
- `LoginItemController.swift`：通过 `SMAppService.mainApp` 注册或注销 macOS 登录项，并以系统实际状态驱动设置开关；界面只展示需要用户处理的异常，非 `.app` 运行模式明确标记为不支持。
- `SSHConfigImportController.swift`、`SSHConfigImportView.swift`：管理发现、手工别名、预览确认、去重、风险提示和批量导入界面。
- `ConfigurationTransferView.swift`：提供逐条导出选择、原生 JSON 文件选择、导入预览、冲突策略和提交结果。
- `AppDelegate.swift`：组装单一 `TunnelManager`、菜单展示、登录项和全局快捷键生命周期，并在应用启动后调度逐连接自动启动。
- `MenuPresentationCoordinator.swift`：创建状态栏项目和可编程控制的主界面面板。
- `GlobalShortcutSystem.swift`：封装 macOS 快捷键注册、注销、事件回调和系统快捷键查询。
- `GlobalShortcutController.swift`：管理启动恢复、录制状态、冲突分类和保存回滚事务。
- `GlobalShortcutSettingsView.swift`、`ShortcutRecorderView.swift`：提供快捷键设置和聚焦录制界面。
- `AppStrings.swift`：App 层本地化入口，负责菜单、按钮、表单、提示和应用生成的错误文案；安装包运行时从 `Contents/Resources` 加载 SwiftPM resource bundle，开发和测试环境回退到 `Bundle.module`。
- `TunnelMenuView.swift`：菜单栏窗口 UI，包括搜索、筛选、排序、启动、停止、打开 URL 和删除；新增及编辑通过独立 `TunnelEditorView` Sheet 完成，主列表卡片不持有表单草稿。
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
3. 把 SwiftPM 生成的本地化 resource bundle 复制到标准的 `.app/Contents/Resources` 目录，由应用的资源定位器加载。
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
dist/SSH Tunnel Manager-0.4.0.zip
```

zip 包使用本机 ad-hoc 签名，不包含 Apple Developer ID notarization，适合可信用户小范围分发。正式公开分发需要后续接入 Developer ID 签名和 notarization。

## 配置模型

配置保存在：

```text
~/Library/Application Support/ssh-tunnel-manager/tunnels.json
```

每个连接组使用 `TunnelConfig` 表示。`id`、`name`、`sshHost`、标签、收藏、手工顺序、最近使用时间、自动重连和自动启动属于连接组；`rules` 中的 `TunnelForwardRule` 独立保存模式、监听端、目标端、URL、启用状态和风险确认签名。

- `id`：隧道唯一标识。
- `rules[].mode`：`localForward`、`remoteForward` 或 `dynamicForward`。
- `rules[].localHost`、`rules[].localPort`、`rules[].remoteHost`、`rules[].remotePort`：按模式表示监听端和目标端。
- `rules[].openURL`、`rules[].isEnabled`：规则级打开地址和启用状态。
- `rules[].riskConfirmationSignature`：与模式、监听地址和端口绑定；修改监听内容后自动失效。
- `sshConfigName`：SSH Config 引用使用。
- `tags`：标签数组，去除首尾空白并按大小写不敏感方式判重；最多 10 个，每个最多 32 个字符。
- `isFavorite`：收藏状态。
- `manualOrder`：唯一稳定的手工顺序序号。
- `lastUsedAt`：最近一次成功启动 SSH 进程的时间；尚未启动时为空。
- `isAutoReconnectEnabled`：是否在可恢复故障后自动重连，兼容默认值为 `false`。
- `isAutoStartEnabled`：是否在应用启动后自动连接，兼容默认值为 `false`。

### 配置类型与规则启用语义

应用内配置分为“连接组”和“SSH Config 引用”两种所有权不同的类型：

- 连接组由应用管理一个 SSH Host 和一个 `rules` 数组。本地、远程和 SOCKS 是规则模式；同一组的全部已启用规则由一个 `/usr/bin/ssh -N` 进程承载。
- SSH Config 引用只保存 Host 别名，Host、`ProxyJump` 和转发指令由用户的 `~/.ssh/config` 管理。应用只读解析和启动，不把其中的转发指令复制为应用内规则，也不改写源文件。

“启用此规则”是规则级状态，只决定该规则是否进入下一次 SSH 参数生成，不表示连接组正在运行，也不替代自动连接或自动重连。停用规则仍完整保存并参与导入、导出；所有规则均停用时允许保存，但连接组不能启动，界面应说明至少需要启用一条转发规则。

新建配置时先选择“连接组”或“SSH Config 引用”。保存后配置类型固定，编辑页不提供两种类型之间的直接切换，避免清空不兼容字段或改变配置所有权。连接组的第一条与后续规则采用相同的数据结构、启用开关、校验、排序和删除行为；SSH Config 引用不显示规则启用控件。

新增和编辑使用同一个 `TunnelEditorView` Sheet。编辑器采用固定标题、独立滚动内容和固定操作区，主列表中的 `TunnelRowView` 始终保持摘要卡片高度。连接组规则使用稳定 UUID 维持身份，一次只展开一条规则的完整字段，其余规则展示紧凑端点摘要；新增规则只在编辑器自己的 `ScrollViewReader` 中定位。`TunnelDraft` 使用值比较判断未保存修改，取消时先确认是否放弃；保存继续调用 `TunnelManager` 的既有校验和事务写入，不绕过端口冲突、SSH Config 解析、危险监听或运行中统一重启确认。由编辑器触发的确认层渲染在 Sheet 内，避免被主面板与 Sheet 的层级遮挡。

旧版单端口 JSON 自动解码为仅含一条规则的连接组，并保留组 UUID、名称和全部组织及自动化元数据。首次写回新结构前原样创建 `tunnels.json.pre-connection-groups.bak`，权限为 `0600`；写入失败不覆盖旧文件且调用方恢复内存数组。

首次把 `remoteForward` 写入已有配置前，`TunnelConfigStore` 会把原始 `tunnels.json` 一次性复制为 `tunnels.json.pre-remote-forward.bak`，权限收紧为 `0600`。备份保留原始字节且不会被后续保存覆盖；降级时退出应用并用该文件替换 `tunnels.json` 即可恢复旧版可读配置。

配置导出使用 `TunnelConfigurationDocument`，当前 `schemaVersion` 为 `2`，顶层字段为 `schemaVersion`、`exportedAt`、`appVersion` 和 `configs`。v2 导出连接组及其规则；导入继续读取 v1 单端口结构并复用本地迁移逻辑。运行进程、stderr、错误历史和凭据不会进入文档；导入预览始终清除规则风险确认。

导入文件上限为 1 MiB、配置上限为 1000 条。解析后先在内存中完成格式版本、必填字段、Host、端口、HTTP/HTTPS URL、标签、重复 UUID、本地监听冲突和暴露监听检查。高于当前版本的格式直接拒绝。相同 UUID 支持跳过、替换和作为副本三种策略，默认跳过；副本生成新 UUID。所有实际导入项强制把 `isAutoStartEnabled` 设为 `false`、把 `lastUsedAt` 置空，自动重连等其他持久化设置保持导出值。

预览阶段只处理数据，不解析 SSH Config、不启动进程、不打开 URL，也不访问登录项或通知权限。提交要求当前没有运行或等待恢复的隧道；`TunnelConfigStore` 先把当前文件原子备份为 `tunnels.json.pre-import.bak` 并收紧为 `0600`，再原子保存合并结果。任何提交错误都会恢复导入前文件和 `TunnelManager` 内存数组。

## 配置组织与展示顺序

`TunnelManager.displayedTunnels` 从持久化配置列表生成只读展示结果：

- 搜索覆盖名称、标签、模式名称、SSH Host 或 SSH Config 别名，以及当前隧道模式实际使用的端口字段；不会把其他模式的占位字段加入搜索文本。
- 标签、仅收藏和搜索条件可以组合；过滤只影响展示，不改变运行时状态。
- 名称、运行状态和最近使用排序均使用确定的次级顺序，避免两秒状态刷新造成无关项目跳动。
- 手工排序只在没有搜索、标签和收藏筛选时显示上下移动入口，避免过滤状态下产生顺序歧义。
- 标签筛选入口按大小写不敏感方式跨配置去重，标签较多时横向滚动，不挤压结果数量和清除入口。

新增配置追加到手工顺序末尾；删除后重新生成连续顺序。收藏、手工顺序和最近使用时间使用事务式内存更新：写盘失败时恢复原配置数组并显示保存错误。运行状态字典按配置 UUID 独立维护，因此筛选和排序不会启动、停止或丢失隧道进程。

配置名称作为用户可见标识，在保存和导入边界使用 `TunnelConfig.nameComparisonKey` 去除首尾空白并按大小写及变音符号不敏感判重。新增与编辑排除自身 UUID 后检查现有列表；SSH Config 批量导入同时检查别名和显示名；JSON 预览只阻止涉及导入项的重名，因此历史重名文件仍可加载和整理。“作为副本”在原名后选择首个可用的 `(2)`、`(3)` 数字后缀。

全局快捷键设置与隧道配置分离，保存在：

```text
~/Library/Application Support/ssh-tunnel-manager/settings.json
```

字段包括设置版本、是否启用、物理键码和修饰键集合。文件不存在时使用默认 `⌃⌥⌘T` 并启用；异常文件不会自动覆盖，应用使用默认值运行并在设置界面提示。两个配置文件都使用原子写入，目录权限为 `0700`，文件权限为 `0600`。

连接通知使用独立的 `connection-notifications.json`，只保存设置版本和是否启用，默认关闭。该文件与快捷键设置使用相同的原子写入和 `0600` 权限，不与隧道配置或快捷键设置互相覆盖。

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

## 四种隧道模式

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

### 远程转发模式

远程转发模式由应用字段生成完整 `-R` 参数：

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -R remoteHost:remotePort:localHost:localPort \
  sshHost
```

其中 `remoteHost:remotePort` 是 SSH 服务器端监听，`localHost:localPort` 是从 Mac 一侧访问的本地目标。远端监听默认 `localhost`；非回环地址和 `*` 在保存及启动前都必须确认，确认内容绑定当前监听地址和端口，并明确提示服务端 `GatewayPorts` 可能扩大实际监听范围。

应用不会执行远端探测命令，也不会用本地 `lsof` 推断远端端口状态。SSH 进程存活时显示 `Running`；`ExitOnForwardFailure=yes` 导致进程退出时显示 stderr 错误。

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

### SSH Config 引用

SSH Config 引用只保存 `sshConfigName`，由 `~/.ssh/config` 中的 Host 条目负责声明 `LocalForward`、`RemoteForward` 或 `DynamicForward`：

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  sshConfigName
```

预览、保存和启动前都会使用固定可执行文件运行：

```bash
/usr/bin/ssh -G sshConfigName
```

应用会解析输出，要求至少存在一条 `localforward`、`remoteforward` 或 `dynamicforward`，并检查监听范围。可能对外暴露的监听会在导入、保存或启动前触发风险确认。每次 `ssh -G` 最长运行 10 秒。

导入流程先在后台只读扫描默认的 `~/.ssh/config`，按 OpenSSH 顺序遍历可访问的 `Include` 文件；通过规范化路径和深度、文件数量上限防止循环或异常配置无限递归。只列出不含 `*`、`?`、`[]` 和否定前缀的明确 Host，重复别名按大小写不敏感处理；通配规则的具体别名可手工输入。扫描阶段不执行 SSH。如果任一已扫描文件含 `Match exec`，首次预览前必须取得用户确认；取消时不会调用 `ssh -G`。预览并发数最多为 4，失败、超时、无转发和重复项都不能导入。批量导入只保存 Host 引用、默认关闭自动重连且不启动连接；源 SSH 配置不写入、不复制。

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

远程转发和 SSH Config 引用不使用本地端口探测，因此运行中按应用进程状态显示 `Running`；如果 SSH 因转发失败退出，stderr 会显示在隧道卡片中。

本地监听探测每轮只运行一次固定的 `/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN`，再用同一份输出判断全部本地和 SOCKS 端点，规则数量不会增加子进程数量。存在运行意图但尚未确认监听时每 2 秒自动检查；确认稳定监听或全部停止后改为每 30 秒检查。启动、停止、保存、导入和用户手工刷新仍立即触发检查，且同一时刻最多存在一个后台状态探测任务。监听结果与当前运行时相同时不写入 `@Published runtimes`，避免主列表发生无意义的 SwiftUI 重新计算和布局。

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
- 手动转发端点、远程转发端点和动态 SOCKS bind host 不允许裸 IPv6，IPv6 必须使用 `[::1]` 形式。
- 本地 bind host 仍允许精确 `*` 以兼容需要局域网访问的场景，但非回环绑定在保存或启动前必须经过明确确认；远端 host 不允许通配符。
- 远程转发的远端监听允许精确 `*`，但非回环监听必须确认；本地目标不允许通配符。
- `127.0.0.1`、`localhost`、`::1` 和 `[::1]` 按回环地址处理；其他本地绑定地址都按可能暴露处理，不进行 DNS 解析。
- SSH Config 引用会检查 `ssh -G` 解析出的本地、远端和动态转发监听地址，并使用相应的风险确认。
- `openURL` 在输入、导入和实际交给系统打开前都只允许带 host 的 `http` 或 `https` URL。
- 端口必须在 `1...65535` 范围内。
- 持久化配置和每个被扫描的 SSH Config 文件在完整读取前检查 1 MiB 上限，并在读取后再次校验，避免异常大文件造成无界内存消耗。

## 错误处理

启动 SSH 时，应用持续读取 stderr，并用 `StderrTailBuffer` 保留最近几行。常见错误包括：

- 本地端口被占用。
- SSH Host 不存在。
- 认证失败或需要扫码登录。
- SSH Config 引用没有本地、远端或动态转发指令。
- `ExitOnForwardFailure=yes` 导致转发失败后 SSH 直接退出。

错误会显示在对应隧道卡片下方，方便用户定位问题。

## 自动重连生命周期

每条运行时记录包含独立的 `TunnelRecoveryState`、SSH 进程、重试任务和稳定运行计时任务。同一配置只有一个运行代次；手工启动、手工停止和网络恢复启动新代次，进程退出回调必须匹配当前代次和进程实例才允许修改状态，因此过期回调不能重启或覆盖新进程。

自动重连默认关闭。启用后，可恢复故障使用 2、5、10、30、60 秒退避，60 秒封顶，稳定运行 5 分钟后清零。认证失败、Host Key 校验失败、端口冲突、转发建立失败和配置错误属于不可重试错误；自动恢复期间的 `ssh -G` 瞬时超时视为可恢复预检查故障并进入下一档退避，手工启动遇到相同超时仍明确失败。网络离线或系统睡眠会取消待执行的重试与稳定计时；恢复后等待网络稳定 2 秒，如果原 SSH 进程仍在运行则继续跟踪，否则仅启动一次新进程。用户在正在连接、等待网络或等待重连阶段停止时会推进运行代次并取消全部任务。

## 登录项与逐连接自动启动

登录项不保存自定义布尔配置，而以 macOS `SMAppService.mainApp.status` 作为事实来源。未注册、已启用和服务未找到等普通内部状态只用于驱动开关，不在界面中单独展示；需要系统批准、当前运行模式不支持或注册操作失败时才显示可操作提示。设置只通过 `register()`、`unregister()` 修改官方登录项。`swift run` 的主 Bundle 不是 `.app`，控制器直接返回不支持并给出安装提示，不调用系统注册接口。登录启动仍保持 `LSUIElement` 菜单栏行为，`AppDelegate` 不主动展示面板。

逐连接自动启动使用 `TunnelConfig.isAutoStartEnabled`，默认关闭且兼容旧 JSON。`AppDelegate` 完成控制器组装后调用 `TunnelManager.startAutomaticallyConfiguredTunnels()`，按持久化顺序逐条处理启用项；每条配置拥有独立运行时，失败不会中断后续项。自动启动沿用自动重连的启动和失败状态机，因此可恢复预检查故障在启用自动重连时进入等待重连，否则进入失败。风险确认只在当前交互操作内有效，应用刚启动时没有有效确认；可能对外暴露的本地、远端或 SSH Config 监听会记录“已跳过自动连接”并进入失败，不创建隐藏确认，也不弹出主界面。关闭登录项只改变 macOS 启动入口，不修改各隧道的 `isAutoStartEnabled`。

## 连接通知与诊断边界

通知控制器不参与 SSH 启停决策。通知默认关闭，只有从设置界面启用时才调用 `UNUserNotificationCenter` 请求权限；拒绝、撤销或投递失败只更新设置提示，不改变隧道状态。系统通知中心委托在应用前台时明确展示横幅、通知中心记录和提示音。每条运行时记录使用 `TunnelNotificationCycle` 标记连续故障周期，首次故障发送一次失败通知；SSH 进程连续存活 2 秒后发送一次恢复通知并结束该周期，若进程在确认窗口内退出则取消待发送的恢复通知，后续退避失败不会重复通知。用户停止、编辑、删除和应用退出都会使运行代次失效并重置通知周期，因此进程终止回调不会产生掉线通知。

运行时只保存已脱敏错误摘要、状态变化时间、退出码、重试次数、下次重试时间和稳定错误类别。复制诊断由 `TunnelDiagnosticReport` 从白名单字段生成，不接受配置名称、端点或原始 stderr 作为输入，从结构上阻止这些内容进入剪贴板。

## 测试策略

`Tests/SSHTunnelCoreTests` 覆盖纯逻辑层：

- JSON 配置读写和旧配置兼容。
- 标签规范化、大小写不敏感判重、数量与长度限制，以及组织元数据往返保存。
- 全局快捷键默认值、有效性校验、稳定编码、配置版本和文件权限。
- 连接组中的本地、远程和动态 SOCKS 规则组合为一个命令，以及 SSH Config 引用命令生成。
- 规则启用状态过滤、稳定顺序、全部规则停用时拒绝启动，以及单组只生成一个 SSH 进程参数数组。
- 远程转发覆盖回环、IPv4、IPv6、通配监听、注入输入和非法端口；首次写入覆盖旧配置原始备份及恢复解码。
- Host、端口、URL 校验。
- SSH Config 的 Include 发现、循环限制、源文件不变和 `Match exec` 检测。
- `ssh -G` 输出中的 `localforward`、`remoteforward`、`dynamicforward` 与监听暴露解析。
- `lsof` 输出中的监听端口解析。
- 运行时状态判定。
- 自动重连退避、稳定运行重置、停止原因、网络与睡眠暂停、过期回调和不可重试故障分类。
- 自动连接兼容默认值、逐连接选择、危险监听拒绝，以及自动重连开关对启动预检查失败状态的影响。
- 通知默认值、私有文件权限、权限拒绝隔离、故障周期去重、错误类别和诊断字段白名单。
- 运行状态、状态摘要和校验错误的中英文展示。
- 托管进程终止等待。
- 隧道统计汇总。
- stderr 最近行缓存。
- 应用版本号。

`Tests/SSHTunnelManagerAppTests` 覆盖 App 层中可抽离的逻辑：

- 新建时明确选择连接组或 SSH Config 引用，已保存配置不显示类型切换入口。
- 连接组的本地、远程和动态 SOCKS 规则显示各自字段，并统一显示“启用此规则”。
- 第一条与后续规则使用一致的编辑、排序、删除和校验行为。
- SSH Config 引用只显示配置别名字段，不显示规则模式或规则启用控件。
- App 层代表性 UI 文案和运行时错误的中英文展示。
- App 层和 Core 层英文、简体中文 `.strings` key 集合一致性。
- 快捷键启动注册、系统冲突、保存提交、持久化失败回滚、停用失败恢复和无修改重试。
- 录制当前活动快捷键时不触发主界面展示。
- 跨配置标签去重、按模式构造搜索字段、手工顺序交换持久化，以及收藏和排序写盘失败回滚。
- SSH Config 导入的确认门槛、三种预览结果、大小写不敏感去重、批量保存和失败回滚。
- 登录项系统状态映射、注册和注销、需要系统批准、`swift run` 不支持提示及失败保持实际状态。

SwiftUI 视图渲染和系统 `Process` 生命周期主要通过编译、核心测试和手动验收验证。

## 手动验收

推荐验收路径：

1. 运行 `swift run ssh-tunnel-manager`。
2. 首次启动确认列表为空，显示“还没有隧道配置”。
3. 添加手动转发隧道，确认保存前会拦截本地端口占用。
4. 启动手动转发隧道，确认状态从 `Running` 变为 `Listening`。
5. 添加动态 SOCKS 隧道，使用脱敏 Host 示例值替换为自己的 SSH Host，确认启动后本地 SOCKS 端口进入 `Listening`。
6. 停止隧道，确认应用只停止自己启动的 SSH 进程。
7. 打开“导入 SSH Config”，确认明确 Host 被发现、已有别名不可重复选择、通配 Host 可手工填写，预览显示转发类型和监听范围。
8. 若配置含 `Match exec`，先取消首次提示并确认没有运行预览，再重新确认；导入后确认 SSH 配置文件哈希不变、新配置未自动连接且自动重连关闭。
9. 添加 SSH Config 引用，确认配置名不存在或没有任何转发指令时保存失败；配置有效 SSH Config 后启动，确认可打开 `openURL`。
10. 修改配置，确认 JSON 文件随之更新；点击删除后先取消，确认配置保留，再次删除并确认后检查配置已从 JSON 文件移除。
11. 分别在英文和简体中文系统语言下启动应用，确认菜单、表单、按钮、状态摘要和应用内错误提示跟随系统语言。
12. 隐藏菜单栏图标后按 `⌃⌥⌘T`，确认主界面显示并置前；再次按键确认主界面关闭。
13. 自定义快捷键并重启应用，确认新组合恢复、旧组合失效。
14. 使用测试辅助进程占用候选组合，确认冲突阻止保存且旧组合继续有效。
15. 在外接显示器和全屏空间中触发快捷键，确认面板位于当前交互屏幕。
16. 确认系统没有请求辅助功能或输入监控权限。
17. 添加带标签的多条脱敏配置，组合使用搜索、标签和仅收藏筛选，确认隐藏配置的运行状态不受影响。
18. 选择手工排序，在无筛选条件下用上下箭头移动配置；重启应用后确认顺序保持。
19. 分别选择名称、运行状态和最近使用排序，确认连接建立阶段 2 秒刷新及稳定监听后的 30 秒刷新均不会打乱同组配置。
20. 使用多个长标签检查横向滚动、结果数量和清除入口均可操作。
21. 添加远程转发并保持远端监听为 `localhost`，确认保存时不显示暴露警告。
22. 把远端监听改为 `*`，确认警告包含当前地址、端口和 `GatewayPorts`，取消后配置不保存，确认后才保存。
23. 在受控 SSH 服务器启动远程转发，确认服务器端端口可访问 Mac 本地目标；停止隧道后确认端口失效。
24. 检查首次保存远程转发前生成的 `tunnels.json.pre-remote-forward.bak`，按恢复步骤确认旧配置可无损读取。
25. 为一条脱敏配置启用自动重连，制造可恢复连接中断，确认重试间隔依次为 2、5、10、30、60 秒且没有高速循环。
26. 在等待重连、正在连接和等待网络阶段分别点击“停止”，确认状态变为“已停止”且之后不再启动。
27. 启动开启自动重连的配置后断网或让 Mac 睡眠，确认期间不重试；恢复后等待 2 秒且只启动一次。
28. 分别制造认证失败、Host Key 失败和端口冲突，确认进入失败状态、保留脱敏错误且不自动重试。
29. 使用安装后的 `.app` 在设置中启用登录时启动，确认重新打开设置后开关保持开启，或明确提示需要系统批准；关闭并重新打开设置后确认开关保持关闭。
30. 使用 `swift run` 打开设置，确认登录项显示仅安装后的 `.app` 可用，且不会伪装注册成功。
31. 分别为两条脱敏配置勾选和取消“应用启动时连接”，重启应用后确认只有勾选项启动；关闭全局登录项后确认逐连接选择仍保留。
32. 同时启用多条自动连接配置并制造其中一条失败，确认其余配置仍继续启动；对非回环监听确认自动启动跳过且主界面不主动弹出。

## 当前边界

当前版本刻意保持简单：

- 只支持 macOS。
- 每个连接组使用一个 SSH Host 和一个受管理 SSH 进程，可以包含多条本地、远程或动态 SOCKS 规则；不支持为组内规则分别指定 SSH Host 或独立运行状态。
- SSH Config 引用会按 Host 中解析出的全部转发指令运行，不提供应用内逐条编辑，也不支持与连接组直接互转。
- 不自动编辑 `~/.ssh/config`。
- 不执行任意远端命令探测远程监听，也不支持远端端口 `0`。

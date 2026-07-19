# mac-ssh-tunnel-manager

English | [中文](README.md)

A lightweight macOS menu bar app for managing SSH local port forwarding, remote port forwarding, and dynamic SOCKS tunnels.

Current version: `0.3.2`

The app name is `SSH Tunnel Manager`; the SwiftPM executable target remains `ssh-tunnel-manager`.

## Features

- Runs as an AppKit icon-only status item with a SwiftUI panel and no Dock icon.
- Enables the global shortcut `⌃⌥⌘T` by default; the shortcut toggles the main panel even when the menu bar icon is hidden.
- Starts tunnels by calling `/usr/bin/ssh` directly, without shell command string assembly.
- Reuses your existing `~/.ssh/config`, ssh-agent, and macOS Keychain behavior.
- Discovers explicit Host aliases from `~/.ssh/config` and accessible `Include` files read-only, with preview and batch import.
- Stores tunnel definitions as local JSON.
- Supports tags, favorites, search, and sorting for organizing tunnel configurations.
- Supports per-tunnel automatic reconnection with network and sleep recovery.
- Supports the official macOS login-item service and starts only tunnels explicitly enabled for connection at app launch; both settings default to off.
- Supports opt-in failure/recovery notifications and copyable diagnostics that omit configuration names, hosts, target ports, and raw stderr.
- Does not store server passwords or private keys.
- Ships with no built-in tunnel presets.
- Supports English and Simplified Chinese UI, following the macOS system language.

## Screenshots

![English tunnel list](docs/assets/screenshots/menu-en.png)

![English add local forward form](docs/assets/screenshots/add-local-forward-en.png)

## Requirements

- macOS 14 or later.
- Xcode 26 or a compatible Swift 6 toolchain.
- SSH Config mode requires a matching `Host` entry in your own `~/.ssh/config`.

## Run From Source

For development:

```bash
swift run ssh-tunnel-manager
```

For manual source-build validation that needs the panel immediately:

```bash
SSH_TUNNEL_MANAGER_SHOW_PANEL=1 swift run ssh-tunnel-manager
```

The environment variable affects only that process. Installed and login-item launches continue to run quietly in the menu bar.

You can also open `Package.swift` in Xcode and run the `ssh-tunnel-manager` executable target.

## Install Locally

To install it as a normal macOS app that can be launched from Finder, Spotlight, or Launchpad:

```bash
./scripts/install-app.sh
```

The script builds a release binary, creates `SSH Tunnel Manager.app`, signs it with local ad-hoc signing, and installs it to:

```text
/Applications/SSH Tunnel Manager.app
```

If an older copy is still running in the menu bar after installation, quit it from the app menu and reopen it. You can also launch it from the command line:

```bash
open -a 'SSH Tunnel Manager'
```

## Package For Distribution

For small trusted distribution:

```bash
./scripts/package-app.sh
```

The zip package is written to:

```text
dist/SSH Tunnel Manager-0.3.2.zip
```

The generated app is ad-hoc signed and is not notarized with an Apple Developer ID. On first launch, macOS may ask the user to approve the app from Finder or from System Settings > Privacy & Security.

## Test

```bash
swift test
```

## Documentation

- [Architecture](docs/architecture.en.md)
- [Distribution](docs/distribution.en.md)
- [Privacy notes](docs/privacy.en.md)
- [Troubleshooting](docs/troubleshooting.en.md)
- [Release process](docs/release.en.md)
- [Automatic reconnection validation](docs/validation-auto-reconnect.md)
- [Connection notification and diagnostics validation](docs/validation-connection-notifications.md)
- [SSH Config read-only import validation](docs/validation-ssh-config-import.md)
- [登录项与逐连接自动启动验收记录（中文）](docs/validation-login-auto-start.md)
- [Changelog](CHANGELOG.en.md)
- [Contributing](CONTRIBUTING.en.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security policy](SECURITY.en.md)
- [License](LICENSE)

## Configuration File

Tunnel definitions are stored at:

```text
~/Library/Application Support/ssh-tunnel-manager/tunnels.json
```

Each tunnel can include these fields:

- `name`
- `mode`
- `sshHost`
- `localHost`
- `localPort`
- `remoteHost`
- `remotePort`
- `sshConfigName`
- `openURL`
- `tags`: up to 10 tags, with a maximum of 32 characters each and case-insensitive deduplication.
- `isFavorite`: whether the tunnel is marked as a favorite.
- `manualOrder`: stable manual sort position.
- `lastUsedAt`: time when the SSH process was most recently started successfully.
- `isAutoReconnectEnabled`: whether recoverable failures should trigger automatic reconnection; defaults to `false` for legacy JSON.
- `isAutoStartEnabled`: whether the tunnel should connect when the app launches; defaults to `false` for legacy JSON.

Legacy JSON without organization, automatic-reconnection, or automatic-connection fields uses compatible defaults. When every configuration lacks `manualOrder`, the original JSON array order becomes the initial manual order.

Connection-notification settings are stored separately at:

```text
~/Library/Application Support/ssh-tunnel-manager/connection-notifications.json
```

The app starts with an empty tunnel list. Add tunnels from the menu bar UI.

Before the first Remote Forward configuration is saved, an existing `tunnels.json` is copied byte-for-byte to:

```text
~/Library/Application Support/ssh-tunnel-manager/tunnels.json.pre-remote-forward.bak
```

## Configuration Organization

The main panel supports combined name, tag, mode, SSH Host or SSH Config alias, and active-port search; tag and favorites filters; result counts; and manual, name, runtime-status, or last-used sorting. Filters and sorting only change presentation and never start, stop, edit, or delete hidden tunnels. Manual order, tags, favorites, and last-used time are persisted with each configuration and rolled back in memory if saving fails.

## Automatic Reconnection

Automatic reconnection is configured independently for each tunnel and is disabled by default. Recoverable SSH failures retry after 2, 5, 10, 30, and 60 seconds, remaining capped at 60 seconds; five minutes of stable operation resets the sequence.

Retries pause while the network is offline or the Mac is asleep. After network recovery or wake, the app waits two seconds for stability and resumes only once. Clicking Stop while connecting, waiting for the network, or waiting to retry cancels the run intent and all pending work. Authentication failures, host-key failures, listener conflicts, and configuration errors do not retry automatically. A transient `ssh -G` timeout during automatic recovery proceeds to the next backoff interval, while the same timeout during a manual start is reported immediately.

## Launch At Login And Automatic Connection

“Launch the app when I log in” is disabled by default. It uses the official macOS `SMAppService.mainApp` mechanism only from an installed `.app`. The toggle follows actual system state, while Settings shows text only when approval, a supported execution mode, or another user action is required. Login items are unavailable under `swift run`; the settings UI explains that an installed app is required instead of reporting false success.

“Connect when the app starts” is also disabled by default for every tunnel and appears with “Reconnect after disconnecting” in the Automation section of the edit form. Manual app launches and login-item launches apply the same rule: only explicitly selected tunnels start, and the app never restores every previously running tunnel. Turning off the global login item preserves per-tunnel selections. An individual failure does not block later tunnels. A potentially exposed local or remote listener is skipped when the new process has no valid risk confirmation and must be started manually for review. Automatic preflight failures enter Waiting to Retry or Failed according to that tunnel's reconnection setting.

## Connection Notifications And Diagnostics

Connection notifications are disabled by default. The app requests macOS notification permission only when the user enables them. Permission denial does not affect tunnel operation. Each continuous failure cycle emits at most one failure notification and one recovery notification after SSH has remained running for two seconds. Notifications remain visible while the panel is open. User-initiated stop, edit, delete, or app quit actions do not emit disconnection notifications.

Connection Details shows the status-change time, exit code, retry count, next retry time, error category, and sanitized error summary. Copy Diagnostics includes only the app and macOS versions, architecture, tunnel mode, status, timestamps, exit code, retry data, and error category. It excludes configuration names, hosts or IPs, usernames, target ports, private-key paths, complete SSH commands, and raw stderr.

## Usage

Click "Add Tunnel" and choose one mode. The examples below use sanitized host names and documentation-only addresses. Replace them with real `Host` aliases from your own `~/.ssh/config`.

### Local Forward

Use this when you want to expose one fixed remote service on a local port, such as a web service, database, or admin port.

```text
Mode: Local Forward
Name: Example Service
SSH Host: example-bastion
Local: 127.0.0.1 18080
Remote: 127.0.0.1 8080
Open URL: http://127.0.0.1:18080
```

If the local bind address is not a loopback address, the app asks for confirmation before saving or starting the tunnel.

The app starts SSH with:

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -L localHost:localPort:remoteHost:remotePort \
  sshHost
```

### Remote Forward

Use this when an SSH server needs to reach a service running on the Mac or reachable from the Mac.

```text
Mode: Remote Forward
Name: Example Reverse
SSH Host: example-bastion
Remote Listener: localhost 18080
Local Target: 127.0.0.1 3000
Open URL: blank
```

The remote listener defaults to `localhost`. A non-loopback address or `*` requires confirmation tied to the current endpoint and warns that the server's `GatewayPorts` setting can widen the effective bind. Runtime status is process-only because a local `lsof` check cannot prove that the remote listener exists.

The app starts SSH with:

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -R remoteHost:remotePort:localHost:localPort \
  sshHost
```

### Dynamic SOCKS

Use this when you want a temporary SOCKS proxy over SSH for command-line tools or apps that support SOCKS proxies. The app only keeps the local SOCKS listener running; it does not modify system proxy settings or Git configuration.

```text
Mode: Dynamic SOCKS
Name: Example SOCKS
SSH Host: example-bastion
SOCKS: 127.0.0.1 1080
Open URL: blank
```

The app starts SSH with:

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -D localHost:localPort \
  sshHost
```

Example one-off Git command:

```bash
ALL_PROXY=socks5h://127.0.0.1:1080 git fetch
```

Keep the SOCKS bind address at `127.0.0.1` unless LAN access is intentional. The app asks for confirmation before using a non-loopback address because other devices may be able to access the proxy.

### SSH Config

Use this when `LocalForward`, `RemoteForward`, or `DynamicForward` rules already live in `~/.ssh/config`. The app stores only the SSH Config alias; it does not copy forwarding directives or edit SSH configuration files.

```sshconfig
Host example-service
  HostName 203.0.113.10
  User appuser
  LocalForward 127.0.0.1:18080 127.0.0.1:8080
```

```text
Mode: SSH Config
Name: Example Service
SSH Config: example-service
Open URL: http://127.0.0.1:18080
```

You can also choose “Import SSH Config” from the bottom of the panel:

1. The app reads `~/.ssh/config` and accessible `Include` files without modifying them, then lists explicit Host aliases without wildcards. Enter a concrete alias manually for wildcard Host patterns.
2. Select aliases and choose “Preview Selected”. The app runs the fixed `/usr/bin/ssh -G <Host>` command and displays forwarding types and listener exposure.
3. If static scanning finds `Match exec`, the app warns before the first preview because `ssh -G` may run its command. Canceling does not invoke `ssh -G`.
4. Existing aliases are not selected again, and only previews containing a forwarding directive can be imported.
5. Importing adds references without connecting and never modifies SSH configuration files.

The app starts SSH with:

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  sshConfigName
```

SSH Config mode requires the selected `Host` to contain at least one `LocalForward`, `RemoteForward`, or `DynamicForward`.

The app checks resolved listeners and asks for confirmation when a local, remote, or dynamic listener may be exposed beyond loopback.

## Safety Boundary

The app only stops SSH processes that it started and tracks itself. It does not search for, attach to, or terminate SSH processes started manually outside the app.

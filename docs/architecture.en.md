# mac-ssh-tunnel-manager Architecture

English | [中文](architecture.md)

## Project Scope

`mac-ssh-tunnel-manager` is the public repository name. The app name is `SSH Tunnel Manager`; the SwiftPM executable target remains `ssh-tunnel-manager`. It is a personal macOS menu bar app for managing SSH local port forwarding, remote port forwarding, and dynamic SOCKS tunnels. It does not implement the SSH protocol and does not store server passwords or private keys. Instead, it starts the system `/usr/bin/ssh` binary directly and reuses the user's existing `~/.ssh/config`, ssh-agent, and macOS Keychain behavior.

Current version: `0.3.2`. The version is defined in `SSHTunnelCore/AppVersion.swift`.

## Module Layout

The project uses SwiftPM. Runtime code is split into two targets:

- `SSHTunnelCore`: pure logic for configuration models, JSON persistence, SSH argument generation, input validation, port-listening parsing, stderr buffering, process termination, status summaries, and version metadata.
- `SSHTunnelManagerApp`: the macOS SwiftUI menu bar app. It owns forms, lists, buttons, status display, and the lifecycle of system SSH `Process` instances.

Both runtime targets include localized resources. The app currently supports English `en` and Simplified Chinese `zh-Hans`, with `en` as the SwiftPM `defaultLocalization`. There is no in-app language switch; runtime UI follows the macOS system language, while tests can force a language through the string wrappers.

Tests are split into two test targets:

- `SSHTunnelCoreTests`: covers core models, command generation, validation, port parsing, status resolution, and configuration persistence.
- `SSHTunnelManagerAppTests`: covers App-layer form display policy that can be tested without rendering SwiftUI views.

Key file responsibilities:

- `TunnelConfig.swift`: tunnel configuration, four tunnel modes, organization metadata, automatic-reconnection settings, and validation errors.
- `CoreStrings.swift`: Core-layer localization entry point for status summaries, runtime statuses, and validation errors.
- `SSHCommandBuilder.swift`: fixed SSH argument generation without shell command string assembly.
- `TunnelConfigStore.swift`: local JSON load/save for tunnel definitions.
- `TunnelRecoveryPolicy.swift`: connection lifecycle, stop reasons, run generations, retry backoff, and SSH failure classification.
- `TunnelDiagnosticSanitizer.swift`: redacts SSH hosts, non-loopback targets, and the user home directory before diagnostics are stored or displayed.
- `PortStatusParser.swift`: parses `lsof` output to detect local listening ports.
- `SSHConfigOutputParser.swift`: parses `ssh -G` output to confirm SSH Config mode has a `LocalForward`.
- `ManagedProcessTerminator.swift`: terminates app-managed processes and waits briefly for exit.
- `TunnelSummary.swift`: summarizes running, failed, and total tunnel counts.
- `TunnelManager.swift`: manages tunnel lists, runtime state, SSH `Process` lifecycle, and validation before saving.
- `SystemRecoveryMonitor.swift`: bridges network path, sleep, and wake events through `NWPathMonitor` and `NSWorkspace` notifications.
- `AppStrings.swift`: App-layer localization entry point for menu text, buttons, forms, help text, and app-generated errors; packaged apps load SwiftPM resource bundles from `Contents/Resources`, while development and tests fall back to `Bundle.module`.
- `TunnelMenuView.swift`: menu bar UI for adding, editing, starting, stopping, opening URLs, and deleting tunnels.
- `TunnelModeFormFields.swift`: centralizes which form fields each tunnel mode should display.
- `scripts/build-app-bundle.sh`: builds the SwiftPM release product into a `.app`, writes `Info.plist`, and applies local ad-hoc signing.
- `scripts/install-app.sh`: reuses the app bundle build script and installs the app to `/Applications`.
- `scripts/package-app.sh`: reuses the app bundle build script and creates a distributable zip under `dist/`.

## Installation Model

For development:

```bash
swift run ssh-tunnel-manager
```

For daily local use, install it as a macOS app:

```bash
./scripts/install-app.sh
```

The install script:

1. Runs `swift build -c release --product ssh-tunnel-manager`.
2. Creates a temporary `SSH Tunnel Manager.app` bundle.
3. Copies SwiftPM-generated localized resource bundles into the standard `.app/Contents/Resources` directory, where the app's resource locator loads them.
4. Reads the current version from `AppVersion.swift` and writes it to `Info.plist`.
5. Declares `CFBundleDevelopmentRegion=en` and `CFBundleLocalizations=en, zh-Hans`.
6. Sets `LSUIElement=true` so the app runs as a menu bar utility without a Dock icon.
7. Applies local ad-hoc signing with `codesign --sign -`.
8. Installs the app to `/Applications/SSH Tunnel Manager.app`.

The install script can be run repeatedly. Reinstalling rebuilds and overwrites the app bundle, but does not remove user tunnel definitions stored in Application Support.

For small trusted distribution:

```bash
./scripts/package-app.sh
```

The package script writes:

```text
dist/SSH Tunnel Manager-0.3.2.zip
```

The zip uses local ad-hoc signing and is not notarized with an Apple Developer ID. Public distribution should add Developer ID signing and notarization later.

## Configuration Model

Tunnel definitions are stored at:

```text
~/Library/Application Support/ssh-tunnel-manager/tunnels.json
```

Each tunnel is represented by `TunnelConfig`. Core fields:

- `id`: unique tunnel identifier.
- `mode`: `localForward`, `remoteForward`, `dynamicForward`, or `sshConfig`.
- `name`: display name in the UI.
- `openURL`: optional local URL to open from the app.
- `sshHost`, `localHost`, `localPort`, `remoteHost`, `remotePort`: used by Local Forward mode.
- `sshHost`, `remoteHost`, `remotePort`, `localHost`, `localPort`: Remote Forward SSH Host, remote listener, and local target.
- `sshHost`, `localHost`, `localPort`: used by Dynamic SOCKS mode.
- `sshConfigName`: used by SSH Config mode.
- `tags`: normalized tags, limited to 10 entries of at most 32 characters and deduplicated case-insensitively.
- `isFavorite`: favorite state.
- `manualOrder`: stable manual sort position.
- `lastUsedAt`: most recent successful SSH process start time.
- `isAutoReconnectEnabled`: whether recoverable failures should reconnect automatically; defaults to `false` for legacy JSON.

Legacy JSON without a `mode` field decodes as `localForward`. Missing organization and automatic-reconnection fields use compatible defaults; when every configuration lacks `manualOrder`, the original JSON array order becomes the initial manual order.

Before the first `remoteForward` write to an existing configuration, `TunnelConfigStore` copies the original bytes to `tunnels.json.pre-remote-forward.bak` with `0600` permissions. Later saves do not overwrite this backup.

## Tunnel Modes

### Local Forward

Local Forward mode generates a complete `-L` argument from app fields:

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -L localHost:localPort:remoteHost:remotePort \
  sshHost
```

The app validates field formats and checks for occupied local ports before saving. It checks the local port again before starting, so it does not accidentally reuse a port already opened outside the app.

### Remote Forward

Remote Forward mode generates a complete `-R` argument:

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -R remoteHost:remotePort:localHost:localPort \
  sshHost
```

`remoteHost:remotePort` is the listener requested on the SSH server, while `localHost:localPort` is the target reached from the Mac side. The listener defaults to `localhost`. Non-loopback addresses and `*` require endpoint-bound confirmation before saving or starting, with an explicit warning that the server's `GatewayPorts` setting can widen the bind.

The app does not run remote probes or use local `lsof` output to claim that the remote port is listening. Runtime state is process-only and forwarding failures are reported from SSH stderr.

### Dynamic SOCKS

Dynamic SOCKS mode generates a complete `-D` argument from app fields:

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -D localHost:localPort \
  sshHost
```

This mode does not declare a fixed remote target. The destination is chosen by the client using the SOCKS proxy. The app validates the SSH Host, bind host, and local port, then checks whether the local port is already occupied before saving and starting. A non-loopback local bind requires confirmation before saving or starting to avoid unintentionally exposing the SOCKS listener.

Sanitized example:

```text
Name: Example SOCKS
SSH Host: example-bastion
SOCKS: 127.0.0.1 1080
Open URL: blank
```

After starting the tunnel, callers still need to opt into the SOCKS proxy themselves, for example:

```bash
ALL_PROXY=socks5h://127.0.0.1:1080 git fetch
```

### SSH Config

SSH Config mode stores only `sshConfigName`; the user's `~/.ssh/config` owns the forwarding declaration:

```bash
/usr/bin/ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  sshConfigName
```

Before saving and starting, the app runs:

```bash
ssh -G sshConfigName
```

It parses the output, requires at least one `localforward`, and checks its local bind address. A non-loopback bind requires confirmation before saving or starting. The `ssh -G` validation has a 10-second timeout so configurations with `Match exec`, `ProxyJump`, or slow DNS are not rejected too aggressively.

## Runtime State

The app only manages SSH processes that it starts. It does not search for or terminate manually started SSH processes.

`TunnelRuntimeState` tracks:

- `process`: the app-started SSH `Process`.
- `isPortListening`: whether the local port is listening for Local Forward and Dynamic SOCKS modes.
- `lastError`: most recent error text.
- `stderrTail`: the last few lines of SSH stderr.

`TunnelRuntimeStatusResolver` maps state to UI statuses:

- `Stopped`: no managed process, no listening port, no error.
- `Running`: managed process is running, but a checked local port is not confirmed listening yet.
- `Listening`: managed process is running and the checked local port is listening.
- `Port occupied`: no managed process, but the local port is already occupied by another process.
- `Failed`: the managed process exited and left an error message.

Remote Forward and SSH Config modes do not use local port probes, so a running process displays as `Running`. If SSH exits because forwarding failed, stderr is shown on the tunnel card.

## Process Cleanup

The app has a "Quit" button at the bottom of the menu. Before quitting, it stops SSH processes started and tracked by this app.

`TunnelManager` also listens for `NSApplication.willTerminateNotification`, so normal system quit paths use the same cleanup path. Cleanup first sends a normal termination signal and waits briefly. During app termination, if a process does not exit in time, the app can force-terminate its own managed process. It never attaches to or kills manually started SSH processes.

## Input And Security Boundary

The app does not accept arbitrary shell commands. All SSH arguments are passed as a `Process.arguments` array to `/usr/bin/ssh`.

Validation rules:

- `sshHost` and `sshConfigName` are required, cannot start with `-`, and cannot contain whitespace, control characters, or obvious shell metacharacters.
- Local Forward, Remote Forward, and Dynamic SOCKS endpoints reject bare IPv6. IPv6 must use bracketed form such as `[::1]`.
- Local bind host still allows exact `*` for intentional LAN access, but non-loopback binds require explicit confirmation before saving or starting; remote host does not allow wildcards.
- A Remote Forward listener allows exact `*`, but non-loopback listeners require confirmation; its local target does not allow wildcards.
- `127.0.0.1`, `localhost`, `::1`, and `[::1]` are treated as loopback addresses. Other local bind values are treated as potentially exposed without DNS resolution.
- SSH Config mode checks the local bind addresses from resolved `LocalForward` entries and uses the same confirmation.
- `openURL` accepts only `http` or `https` URLs with a host.
- Ports must be in `1...65535`.

## Error Handling

When starting SSH, the app reads stderr continuously and keeps the last few lines in `StderrTailBuffer`.

Common errors include:

- Local port already occupied.
- SSH Host does not exist.
- Authentication failed or requires interactive approval.
- SSH Config mode has no `LocalForward`.
- `ExitOnForwardFailure=yes` makes SSH exit when forwarding fails.

Errors are shown under the affected tunnel card.

## Automatic Reconnection Lifecycle

Each runtime record owns an independent `TunnelRecoveryState`, SSH process, retry task, and stable-operation timer. Manual start, manual stop, and recovery advance a run generation. Process termination callbacks may mutate state only when both the generation and process instance still match, preventing stale callbacks from restarting or overwriting a newer run.

Automatic reconnection is disabled by default. When enabled, recoverable failures use 2, 5, 10, 30, and 60 second backoff intervals capped at 60 seconds; five minutes of stable operation resets the sequence. Authentication failures, host-key failures, listener conflicts, forwarding failures, and configuration errors are permanent failures. A transient `ssh -G` timeout during automatic recovery is retried at the next interval, while a manual start reports it immediately. Network loss or sleep cancels pending retry and stability tasks. Recovery waits two seconds for network stability and starts at most one replacement process. Stop advances the generation and cancels all pending work even while connecting or waiting.

## Test Strategy

`Tests/SSHTunnelCoreTests` covers core logic:

- JSON persistence and legacy configuration compatibility.
- Command generation for Local Forward, Dynamic SOCKS, and SSH Config modes.
- Host, port, and URL validation.
- `localforward` parsing from `ssh -G` output.
- Listening-port parsing from `lsof` output.
- Runtime status resolution.
- Automatic-reconnection backoff and reset, stop reasons, network and sleep pauses, stale callbacks, and permanent-failure classification.
- English and Simplified Chinese display text for runtime statuses, summaries, and validation errors.
- Managed process termination.
- Tunnel summary counts.
- stderr tail buffering.
- App version metadata.

`Tests/SSHTunnelManagerAppTests` covers App-layer logic that can be separated from SwiftUI rendering:

- Local Forward shows SSH Host, local, and remote fields, but not SSH Config fields.
- Dynamic SOCKS shows only SSH Host and SOCKS local listener fields, not remote or SSH Config fields.
- SSH Config shows only the config alias field.
- Representative App-layer UI text and runtime errors in English and Simplified Chinese.
- Matching key sets across English and Simplified Chinese `.strings` files for both App and Core layers.

SwiftUI rendering and system `Process` lifecycle are mainly validated by compilation, core tests, and manual acceptance testing.

## Manual Acceptance

Recommended manual flow:

1. Run `swift run ssh-tunnel-manager`.
2. Confirm the first launch shows an empty list.
3. Add a Local Forward tunnel and confirm occupied local ports are rejected before saving.
4. Start the Local Forward tunnel and confirm status moves from `Running` to `Listening`.
5. Add a Dynamic SOCKS tunnel with a sanitized Host replaced by your own SSH Host and confirm the local SOCKS port reaches `Listening`.
6. Stop the tunnel and confirm the app only stops SSH processes it started.
7. Add an SSH Config tunnel and confirm nonexistent config names or configs without `LocalForward` are rejected.
8. Start a valid SSH Config tunnel and confirm `openURL` works.
9. Edit a tunnel and confirm the JSON file updates. Start deleting it and cancel to confirm the configuration remains, then confirm deletion and verify it is removed from the JSON file.
10. Launch the app with English and Simplified Chinese system languages and confirm menus, forms, buttons, status summaries, and app-generated errors follow the system language.
11. Enable automatic reconnection for a sanitized test tunnel, interrupt a recoverable connection, and confirm the 2, 5, 10, 30, and 60 second sequence without a tight retry loop.
12. Stop while Connecting, Waiting for Network, and Waiting to Retry, and confirm the tunnel remains stopped.
13. Disconnect the network or sleep the Mac while an enabled tunnel is running; after recovery, confirm it waits two seconds and starts only one replacement process.
14. Trigger authentication, host-key, and local-port-conflict failures and confirm they remain failed without automatic retries and expose only sanitized diagnostics.

## Current Boundaries

The current version intentionally stays small:

- macOS only.
- Each configuration contains one Local Forward, Remote Forward, Dynamic SOCKS, or SSH Config forwarding rule; multi-rule profiles are not supported.
- Does not edit `~/.ssh/config`.
- Does not install a login item.
- Does not run arbitrary remote probes to verify Remote Forward listeners or support remote port `0`.

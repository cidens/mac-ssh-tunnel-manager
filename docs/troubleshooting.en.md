# Troubleshooting

[中文](troubleshooting.md) | English

This document covers common issues and diagnostic steps. Before posting public feedback, sanitize real Hosts, IPs, usernames, private-key paths, and full SSH configuration.

## Launch At Login Is Unavailable Or Requires Approval

Login items are supported only by an installed `SSH Tunnel Manager.app`. When running with `swift run`, Settings explicitly reports that an installed app is required. Install it first:

```bash
./scripts/install-app.sh
```

If the app says approval is required, allow `SSH Tunnel Manager` in System Settings > General > Login Items & Extensions, then reopen the app settings to confirm the toggle. The app shows a message only when user action is required; the toggle itself represents the normal enabled or disabled state.

The current distribution uses ad-hoc signing. After rebuilding and replacing a development test package, macOS may identify it as a new app version; turn Launch at Login on again and save. Do not move or delete `/Applications/SSH Tunnel Manager.app` after registration.

Turning off Launch at Login removes only the global login item. It preserves every tunnel's Connect When the App Starts selection.

## A Selected Tunnel Does Not Connect When The App Starts

Edit the tunnel and confirm Connect When the App Starts is selected in the Automation section. The app never restores every previously running tunnel; it processes only explicit per-tunnel selections.

- An exposed listener is skipped during an unattended launch because it requires an active risk confirmation. Start it manually from the panel to review the warning.
- Waiting to Retry means automatic reconnection is also enabled and a recoverable preflight check failed.
- Failed means the preflight or connection could not continue. Check the card error or Connection Details. One failure does not block other selected tunnels.
- Launch at Login controls whether macOS opens the app automatically. Opening the app manually applies the same per-tunnel automatic-connection rule.

## Local Port Already In Use

Symptom:

```text
Address already in use
Could not request local forwarding.
```

Usually this means the same local address and port are already being listened on by another process. It may also mean the same tunnel is already running in another app instance.

Check:

```bash
lsof -nP -iTCP:<local-port> -sTCP:LISTEN
```

Fix options:

- Stop the process occupying that port.
- Choose another local port.
- Confirm that multiple `SSH Tunnel Manager.app` instances are not running at the same time.

## The App Warns That A Local Listener May Be Exposed

When Local Forward, Dynamic SOCKS, or a resolved SSH Config local, remote, or dynamic listener uses a non-loopback bind address, the app asks for confirmation before importing, saving, or starting.

The default recommendation is:

```text
127.0.0.1
```

If you continue, other devices on the LAN may access a fixed forwarded service. In Dynamic SOCKS mode, they may also use the listener as a proxy. Use `*`, `0.0.0.0`, or another non-loopback address only when LAN access is intentional.

## Command-Line Tools Do Not Automatically Use SOCKS

Dynamic SOCKS mode only starts a local SOCKS listener. It does not modify system proxy settings, browser proxy settings, or command-line tool configuration. Commands that should use SOCKS must explicitly opt into the proxy:

```bash
ALL_PROXY=socks5h://127.0.0.1:<local-port> curl https://example.com
```

Replace `<local-port>` with the local port configured in the app.

If a command still connects directly to the target service, it usually means the command does not read the proxy environment variable or the app has its own proxy setting.

## SSH Config Import Does Not List A Host

Import lists only explicit Hosts from `~/.ssh/config` and accessible `Include` files. It does not turn `Host *`, `Host *.example`, or negated patterns into concrete aliases automatically.

Fix options:

- Check the top of the import panel for unreadable Include files, invalid syntax, or traversal-limit warnings.
- Confirm that each Include path exists and is readable by the current user.
- For a wildcard Host, expand “Concrete alias for wildcard Host (optional)”, enter the complete alias you actually use, and preview it.
- If an explicit Host is still missing, close and reopen the import panel to rescan the files.

Entering an alias adds only a preview candidate; it does not create or modify SSH Config.

## SSH Config Mode Reports A Missing Forwarding Directive

An SSH Config reference requires the selected Host to contain at least one `LocalForward`, `RemoteForward`, or `DynamicForward`. Example:

```sshconfig
Host example-service
  HostName 203.0.113.10
  User appuser
  LocalForward 127.0.0.1:18080 127.0.0.1:8080
```

Check the final OpenSSH configuration:

```bash
ssh -G example-service | grep -Ei '^(localforward|remoteforward|dynamicforward) '
```

If there is no output, the app rejects saving or starting that configuration.

## SSH Config Uses ProxyJump Or Match exec

The app runs `ssh -G <Host>` for previews and before saving. Import warns first when static scanning finds `Match exec`; complex configurations may still exceed the 10-second timeout because of `Match exec`, `ProxyJump`, or slow DNS.

Fix options:

- Run `ssh -G example-service` in Terminal and confirm whether it is slow or failing.
- Simplify the Host config and retry.
- Confirm the jump host and DNS are reachable.

## First Launch Says The Developer Cannot Be Verified

The current distribution package uses local ad-hoc signing and is not notarized with an Apple Developer ID. Gatekeeper may block the first launch.

Fix options:

- Right-click `SSH Tunnel Manager.app` in Finder and choose "Open".
- If macOS still blocks the app, allow it from System Settings > Privacy & Security.

## UI Does Not Change After Switching System Language

The app follows the macOS system language, but it does not switch language while running. Quit and restart the app after changing the system language.

## Which SSH Processes Are Closed On Quit

The app only closes SSH processes that it started and recorded. It does not actively terminate SSH sessions started manually from Terminal.

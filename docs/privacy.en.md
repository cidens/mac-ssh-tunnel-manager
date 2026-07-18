# Privacy Notes

[中文](privacy.md) | English

`ssh-tunnel-manager` is a local macOS menu bar tool. The current version does not include accounts, telemetry, cloud sync, or remote configuration services.

## Data Stored Locally

The app stores tunnel definitions at:

```text
~/Library/Application Support/ssh-tunnel-manager/tunnels.json
```

The configuration may contain:

- Tunnel names.
- SSH Host aliases.
- Local listening addresses and ports.
- Remote addresses and ports; Remote Forward includes the remote listener and local target.
- SSH Config Host names.
- Optional open URLs.

Connection-notification settings are stored in `connection-notifications.json` in the same Application Support directory. The file contains only a schema version and the enabled flag. The app requests macOS notification permission only when the user enables notifications, and notification content omits tunnel names, hosts, addresses, and ports.

Before the first Remote Forward configuration is saved, the app may create `tunnels.json.pre-remote-forward.bak` in the same directory. It is a local recovery copy containing the same categories of information as `tunnels.json` and is not uploaded.

The app does not store:

- SSH passwords.
- Private-key contents.
- Tokens.
- ssh-agent credentials.
- macOS Keychain credentials.

## Network Behavior

The app itself does not proactively connect to third-party services. When a tunnel starts, the app calls the system `/usr/bin/ssh` binary, and SSH connects according to the Host value or the user's `~/.ssh/config`.

Dynamic SOCKS mode only starts a local SOCKS listener. It does not modify system proxy settings, browser proxy settings, or Git configuration. The user decides which commands or apps send traffic through the tunnel.

Remote Forward mode asks the SSH server to create a remote listener and forwards connections to a target on or reachable from the Mac. The effective listener may be affected by the server's `GatewayPorts` setting; the app does not change that setting.

## Local Process Behavior

The app only tracks and stops SSH processes that it started. It does not scan, attach to, or terminate SSH sessions started manually by the user.

## Privacy Reminder For Public Feedback

Copy Diagnostics generates a structured shareable summary containing versions, system architecture, tunnel mode, state, timestamps, exit code, retry data, and error category. It excludes configuration names, hosts or IPs, usernames, target ports, private-key paths, complete SSH commands, and raw stderr.

Before submitting issues, screenshots, or logs, sanitize:

- Real Host names, private IPs, public IPs, and domains.
- Usernames, organization names, and project names.
- Private-key paths, certificate paths, tokens, and passwords.
- Full SSH configuration content.

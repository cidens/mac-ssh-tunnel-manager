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
- Remote addresses and ports.
- SSH Config Host names.
- Optional open URLs.

The app does not store:

- SSH passwords.
- Private-key contents.
- Tokens.
- ssh-agent credentials.
- macOS Keychain credentials.

## Network Behavior

The app itself does not proactively connect to third-party services. When a tunnel starts, the app calls the system `/usr/bin/ssh` binary, and SSH connects according to the Host value or the user's `~/.ssh/config`.

Dynamic SOCKS mode only starts a local SOCKS listener. It does not modify system proxy settings, browser proxy settings, or Git configuration. The user decides which commands or apps send traffic through the tunnel.

## Local Process Behavior

The app only tracks and stops SSH processes that it started. It does not scan, attach to, or terminate SSH sessions started manually by the user.

## Privacy Reminder For Public Feedback

Before submitting issues, screenshots, or logs, sanitize:

- Real Host names, private IPs, public IPs, and domains.
- Usernames, organization names, and project names.
- Private-key paths, certificate paths, tokens, and passwords.
- Full SSH configuration content.

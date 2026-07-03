# Troubleshooting

[中文](troubleshooting.md) | English

This document covers common issues and diagnostic steps. Before posting public feedback, sanitize real Hosts, IPs, usernames, private-key paths, and full SSH configuration.

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

## Command-Line Tools Do Not Automatically Use SOCKS

Dynamic SOCKS mode only starts a local SOCKS listener. It does not modify system proxy settings, browser proxy settings, or command-line tool configuration. Commands that should use SOCKS must explicitly opt into the proxy:

```bash
ALL_PROXY=socks5h://127.0.0.1:<local-port> curl https://example.com
```

Replace `<local-port>` with the local port configured in the app.

If a command still connects directly to the target service, it usually means the command does not read the proxy environment variable or the app has its own proxy setting.

## SSH Config Mode Reports Missing LocalForward

SSH Config mode requires the selected Host to contain at least one `LocalForward`. Example:

```sshconfig
Host example-service
  HostName 203.0.113.10
  User appuser
  LocalForward 127.0.0.1:18080 127.0.0.1:8080
```

Check the final OpenSSH configuration:

```bash
ssh -G example-service | grep -i '^localforward '
```

If there is no output, the app rejects saving or starting that configuration.

## SSH Config Uses ProxyJump Or Match exec

The app runs `ssh -G <Host>` before saving to validate the config. Complex configurations may time out because of `Match exec`, `ProxyJump`, or slow DNS.

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

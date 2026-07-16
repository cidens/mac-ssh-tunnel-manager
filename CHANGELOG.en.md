# Changelog

[中文](CHANGELOG.md) | English

This project follows the basic Semantic Versioning convention: patch releases for fixes, minor releases for backward-compatible features, and major releases for breaking changes.

## 0.3.0

- Adds a customizable global shortcut, using `⌃⌥⌘T` by default. Triggering it shows and brings the main panel to the front; triggering it again closes the panel.
- Adds shortcut recording, enable or disable controls, default restoration, and settings in English and Simplified Chinese. Conflicts recognizable by the system are checked before saving, and failed saves preserve the previous settings.
- Changes the menu bar entry to an icon-only item with a tooltip, reducing menu bar space usage.
- Makes the tunnel list independently scrollable while keeping “Add Tunnel” and “Quit” fixed at the bottom of the panel.

## 0.2.1

- Adds explicit risk confirmation for non-loopback local bind addresses in Local Forward, Dynamic SOCKS, and SSH Config `LocalForward` entries.
- Fixes a potential block or timeout caused by leaving the SSH Config validation stderr pipe unread.
- Adds tests for non-loopback bind confirmation, SSH Config parsing, and related localization.

## 0.2.0

Initial public release.

- Supports macOS menu bar management for SSH local port forwarding.
- Supports dynamic SOCKS tunnels.
- Supports SSH Config mode for reusing existing `LocalForward` entries from `~/.ssh/config`.
- Supports English and Simplified Chinese UI, following the macOS system language.
- Stores tunnel definitions as local JSON and does not store server passwords or private keys.
- Provides local install scripts and small-scale zip distribution scripts.
- Adds architecture, distribution, privacy, security, contributing, release, and troubleshooting documentation.

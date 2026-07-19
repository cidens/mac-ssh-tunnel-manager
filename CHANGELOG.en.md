# Changelog

[中文](CHANGELOG.md) | English

This project follows the basic Semantic Versioning convention: patch releases for fixes, minor releases for backward-compatible features, and major releases for breaking changes.

## Unreleased

- Moves Add and Edit out of inline list cards into a dedicated sheet so the main list stays compact and stable. Multi-rule forms expand one rule at a time, keep the title and actions visible, and confirm before discarding unsaved changes.
- Groups connect-on-launch and automatic reconnection into a separate Automation card, visually separating them from basic fields and forwarding rules.
- Makes tunnel display names unique after trimming and case-insensitive comparison. Add, Edit, and imports reject conflicts, while JSON Import as Copy appends a numeric suffix.
- Reduces local-listener status overhead by taking one `lsof` snapshot per refresh, polling every two seconds only while a Local/SOCKS listener is being established, then every 30 seconds after listening is confirmed. Unchanged results no longer publish runtime state or trigger redundant SwiftUI rendering, while event and manual refreshes remain immediate.
- Tightens local data boundaries with a 1 MiB limit for persisted configuration and each scanned SSH Config file, plus a final HTTP/HTTPS-with-host check before opening URLs.
- Adds connection groups so one SSH Host and one SSH process can carry mixed Local, Remote, and Dynamic SOCKS rules. New configurations explicitly choose a Connection Group or SSH Config Reference, saved types cannot be converted in place, each rule clearly controls whether it participates, and start, stop, reconnect, and connect-on-launch remain group-level operations.
- Upgrades configuration export to `schemaVersion = 2`, keeps read-only schema v1 import, and safely migrates released single-forward `tunnels.json` files after creating a byte-for-byte recovery backup.
- Adds default-disabled macOS login-item registration and per-tunnel Connect When the App Starts. The app uses `SMAppService.mainApp`, drives the toggle from actual system state while showing only actionable feedback, applies the same connection selection to manual and login launches, skips risky listeners without a valid confirmation, and continues starting other selected tunnels after an individual failure.
- Adds read-only SSH Config discovery and batch import across accessible `Include` files, case-insensitive duplicate handling, `/usr/bin/ssh -G` previews for `LocalForward`, `RemoteForward`, `DynamicForward`, and listener exposure, confirmation before configurations containing `Match exec` are evaluated, reference-only imports that do not connect, and risk confirmation for potentially exposed listeners.
- Adds opt-in connection failure and recovery notifications, requests permission only when enabled, limits each continuous failure cycle to one failure and one recovery notification, and suppresses disconnection notifications for user actions.
- Adds Connection Details and Copy Diagnostics with status time, exit code, retry data, error category, and a sanitized summary; copied output excludes configuration names, hosts or IPs, usernames, target ports, private-key paths, complete commands, and raw stderr.
- Adds opt-in per-tunnel automatic reconnection with 2, 5, 10, 30, and 60 second backoff intervals and a reset after five minutes of stable operation.
- Adds Connecting, Waiting for Network, and Waiting to Retry states; retries pause while offline or asleep and resume once after the network remains stable for two seconds.
- Isolates stale process callbacks by run generation; manual Stop cancels retries, while authentication, host-key, port-conflict, and configuration failures do not retry automatically.
- Adds OpenSSH remote port forwarding with `-R`, including remote listener and local target fields, risk confirmation for non-loopback remote binds, and a recoverable pre-migration configuration backup.
- Fixes local port status refresh blocking the main thread and the menu panel failing to remain visible while the app is inactive.
- Adds tunnel tags, favorites, search, combined filters, result counts, and a clear-filter action.
- Adds manual, name, runtime-status, and last-used sorting; persists manual order and last-used time with rollback on save failure while preserving legacy JSON order.
- Trims tags, deduplicates them case-insensitively, and limits each tunnel to 10 tags of at most 32 characters.
- Adds horizontal scrolling for long tag lists, mode-aware search fields, and configuration-compatibility and sort-persistence tests.

## 0.3.2

- Fixes distribution packages failing to load SwiftPM localization resources from the standard `Contents/Resources` directory, which caused the app to exit immediately away from the build machine, and validates the runtime resource layout during Release builds.

## 0.3.1

- Adds confirmation before deleting a tunnel configuration, explains that deletion cannot be undone, and warns that a running tunnel will be stopped first.
- Adds a default pull request template, issue entry points, a code of conduct, and private vulnerability reporting guidance.
- Adds GitHub Actions dependency updates, generated release notes, and a tag-triggered automated Release workflow.

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

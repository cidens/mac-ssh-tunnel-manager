# Distribution Guide

English | [中文](distribution.md)

## Scope

The current distribution flow is intended for small trusted distribution, such as your own Macs, friends, or coworkers. It does not require the Apple Developer Program and does not use Developer ID notarization.

For broad public distribution, the project should later add Developer ID signing, notarization, and a DMG or release workflow.

## Create A Distribution Package

Run this from the repository root:

```bash
./scripts/package-app.sh
```

The script:

1. Builds `ssh-tunnel-manager` in SwiftPM release mode.
2. Creates `SSH Tunnel Manager.app`.
3. Copies SwiftPM-generated localized resource bundles into the standard `.app/Contents/Resources` directory, where the app's resource locator loads them.
4. Writes `Info.plist` with version metadata, menu bar app settings, minimum system version, and `en` plus `zh-Hans` localization declarations.
5. Applies local ad-hoc signing.
6. Creates a zip package under `dist/`.

Example output:

```text
dist/SSH Tunnel Manager-0.3.2.zip
```

`dist/` is a build output directory and should not be committed to Git.

## User Installation

After receiving the zip package, users install it like this:

1. Unzip `SSH Tunnel Manager-0.3.2.zip`.
2. Drag `SSH Tunnel Manager.app` to `/Applications`.
3. Open the app from Finder, Spotlight, or Launchpad.
4. Add tunnel definitions based on their own `~/.ssh/config`.

The app ships with no default tunnel definitions and does not store SSH passwords or private keys.

The UI supports English and Simplified Chinese and follows the user's macOS system language. Restart the app after changing the system language.

## Gatekeeper Warning

The current zip package uses ad-hoc signing and does not include Apple Developer ID notarization. On first launch, macOS may say that it cannot verify the developer.

Common workarounds:

- Right-click `SSH Tunnel Manager.app` in Finder and choose "Open".
- If macOS still blocks the app, allow it from System Settings > Privacy & Security.

This is acceptable for small trusted distribution. For smoother double-click installation, add Developer ID signing and notarization later.

## Updating Versions

### Update A Locally Installed App

On a development Mac or your own Mac, update `/Applications/SSH Tunnel Manager.app` from the repository root:

```bash
./scripts/install-app.sh
```

The script rebuilds the release binary, creates the `.app`, applies local ad-hoc signing, and overwrites:

```text
/Applications/SSH Tunnel Manager.app
```

If the older version is still running in the menu bar, quit it from the app menu and reopen it from Finder, Spotlight, Launchpad, or:

```bash
open -a 'SSH Tunnel Manager'
```

### Update A Distribution Package

When you need to send a new build to other users, rerun:

```bash
./scripts/package-app.sh
```

Send the new zip. Users should quit the old app and replace `/Applications/SSH Tunnel Manager.app` with the new one.

Tunnel definitions are stored at:

```text
~/Library/Application Support/ssh-tunnel-manager/tunnels.json
```

Replacing the app bundle does not delete existing tunnel definitions.

## Tunnel Configuration Notes

The app supports four modes:

- Local Forward: generates `ssh -N -L localHost:localPort:remoteHost:remotePort sshHost`.
- Remote Forward: generates `ssh -N -R remoteHost:remotePort:localHost:localPort sshHost`; non-loopback remote listeners require confirmation, and the effective bind depends on the server's `GatewayPorts` setting.
- Dynamic SOCKS: generates `ssh -N -D localHost:localPort sshHost`, useful for one-off SOCKS proxy use by Git, curl, browsers, or similar tools.
- SSH Config: passes only `sshConfigName`; the user's own `~/.ssh/config` provides `LocalForward`, `RemoteForward`, or `DynamicForward`, and read-only import stores only the Host reference.

Examples use sanitized values such as `example-bastion`, `example-service`, and `203.0.113.10`. Do not publish real Host aliases, private IPs, usernames, or private-key paths in public documentation or release notes.

Before the first Remote Forward configuration is saved, the app backs up an existing `tunnels.json` as `tunnels.json.pre-remote-forward.bak`. Quit the app before replacing `tunnels.json` with this backup for downgrade recovery.

# Contributing

[中文](CONTRIBUTING.md) | English

Issues and pull requests are welcome. This project intentionally stays small and focused. The main priorities are stable SSH argument generation, clear safety boundaries, reliable port status detection, and a simple macOS menu bar experience.

## Local Development

Requirements:

- macOS 14 or later.
- Xcode 26 or a compatible Swift 6 toolchain.

Run tests:

```bash
swift test
```

Run from source:

```bash
swift run ssh-tunnel-manager
```

Build a local app bundle:

```bash
./scripts/build-app-bundle.sh /private/tmp/SSH\ Tunnel\ Manager.app
```

## Pre-Commit Checks

Before submitting changes, run at least:

```bash
swift test
git diff --check
```

If your change affects packaging, resources, localization, or `Info.plist`, also run:

```bash
./scripts/build-app-bundle.sh /private/tmp/SSH\ Tunnel\ Manager.app
```

## Sanitizing Documentation And Examples

Do not include real environment details in public issues, pull requests, documentation, or tests:

- Real Host aliases, private IPs, public IPs, or domains.
- Usernames, company names, or project names.
- Tokens, passwords, private-key paths, or certificate paths.
- Full `~/.ssh/config` content.

Use sanitized examples:

- `example-bastion`
- `example-service`
- `203.0.113.10`
- `127.0.0.1`
- `appuser`

## Code Guidelines

- Do not start SSH through shell command strings; continue using `Process.arguments`.
- When adding user-visible text, update both English and Simplified Chinese `.strings` files for the App/Core layer.
- Do not change the `tunnels.json` structure unless migration notes and tests are included.
- Do not edit the user's `~/.ssh/config` automatically.
- Do not terminate SSH processes that were not started and tracked by this app.

## Pull Request Notes

PR descriptions should include:

- Purpose of the change.
- Main implementation points.
- Test commands and results.
- Whether the change touches safety boundaries, SSH arguments, localization, or packaging.

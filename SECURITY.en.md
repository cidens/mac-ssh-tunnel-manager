# Security Policy

[中文](SECURITY.md) | English

`ssh-tunnel-manager` starts the system `/usr/bin/ssh` binary and inspects local listening ports. Please report security issues carefully and avoid posting real environment details in public issues.

## Supported Versions

Only the latest public version and the `main` branch are maintained. Older versions do not have a long-term security maintenance commitment.

## Reporting Security Issues

GitHub Private Vulnerability Reporting is enabled for this repository. Report security issues through the private channel below instead of opening a public issue:

- [Open a private vulnerability report](https://github.com/cidens/mac-ssh-tunnel-manager/security/advisories/new)

Include the affected version, minimal reproduction steps, expected impact, and a note confirming that the report has been sanitized. If the private channel is temporarily unavailable, open a sanitized issue without technical details stating that the private security channel is unavailable.

- A possible arbitrary command execution issue.
- Possible leakage of SSH Host aliases, usernames, private IPs, private-key paths, or local configuration.
- Incorrect termination of SSH processes not started by this app.
- Input validation bypasses that affect SSH argument generation.

## Information Not To Post Publicly

Sanitize reports before posting:

- Real SSH Host aliases.
- Private IPs, public IPs, and domains.
- Usernames, organization names, and project names.
- Private-key paths, certificate paths, tokens, and passwords.
- Full `~/.ssh/config` content.

Use placeholders such as:

- `example-bastion`
- `example-service`
- `203.0.113.10`
- `127.0.0.1:18080`

## Response Expectations

This is a small personally maintained tool, so there is no fixed response SLA. Confirmed issues affecting local safety boundaries, process management, or SSH argument generation will be prioritized.

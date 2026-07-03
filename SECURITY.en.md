# Security Policy

[中文](SECURITY.md) | English

`ssh-tunnel-manager` starts the system `/usr/bin/ssh` binary and inspects local listening ports. Please report security issues carefully and avoid posting real environment details in public issues.

## Supported Versions

Only the latest public version and the `main` branch are maintained. Older versions do not have a long-term security maintenance commitment.

## Reporting Security Issues

If you find one of the following issues, please prefer GitHub Security Advisory. If the repository does not have that feature enabled, open a sanitized issue saying that a potential security issue needs private follow-up, without posting sensitive details.

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

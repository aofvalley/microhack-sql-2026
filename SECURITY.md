# Security Policy

## Supported versions

Only the latest commit on `main` is supported.

## Reporting a vulnerability

If you discover a security issue (e.g., a script that inadvertently exposes
credentials, a misconfigured NSG rule, or a hard-coded secret), please
**do not open a public issue**.

Use GitHub's private vulnerability reporting:

> Repository -> Security tab -> "Report a vulnerability"

We aim to acknowledge reports within 48 hours and publish a fix within 7 days
for critical issues.

## Security posture

- All VMs are accessible **only via Azure Bastion** (no public IPs).
- NSG rules deny all inbound traffic except Bastion-sourced RDP and intra-VNet SQL.
- **Never use production credentials or databases in this lab.**
- The `users.csv` file is `.gitignore`d and must be treated as sensitive.

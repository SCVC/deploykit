# Security Policy

deploykit configures security agents (SIEM, remote support, osquery, managed browser) on staff
devices, so we hold it to a high bar.

## Reporting a vulnerability

**Do not open a public issue for security problems.**

Use GitHub's **private vulnerability reporting** for this repository:
**Security → Report a vulnerability** (Security Advisories). This routes the report privately to
the maintainers. Please include reproduction steps and the affected file(s)/platform.

We aim to acknowledge within a few business days and to fix or mitigate confirmed issues promptly.

## Scope

In scope:

- Secrets, tokens, or internal hostnames leaking into the repo or an installer URL.
- A script fetching/executing an installer over an untrusted channel, or without integrity checks.
- Privilege-escalation or destructive behaviour in the setup/onboarding/offboarding scripts.
- Cloudflare Access / enrollment credentials handled unsafely.

Out of scope:

- Vulnerabilities in the upstream vendor agents themselves (report those to the vendor).
- A missing `config.env` (expected — it is supplied per deployment and never committed).

## Handling secrets

This repository is **public and must contain zero secrets**. All sensitive values live in a
git-ignored `config.env`. The `secret-scan` CI gate blocks any commit that tracks `config.env`
or introduces a known internal host/token. If you believe a secret was committed, report it
privately as above so it can be rotated and purged from history.

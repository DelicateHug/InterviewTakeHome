# [04] Conditional Access (phishing-resistant MFA)

**Type:** Entra CA policy (doc-only)

> **In plain terms —** An Entra sign-in rule that would force phishing-resistant MFA (FIDO2 keys / passkeys / Windows Hello) for AWS admins. Written as code but left switched off so it doesn't change the live tenant.

## Controls applied

- **Prevention:** Requires auth strength = built-in **Phishing-resistant MFA** (`...0004`); the only accepted grant, so non-MFA / weak MFA is blocked. Written as IaC but **disabled** (guardrail).
- **Detection:** Entra sign-in logs.
- **Alert:** Entra Identity Protection (recommended).

## What would trigger an alert

- A user tries to sign in with a weak factor (password or SMS only) → grant denied and logged as a failed sign-in in Entra, once the policy is enabled.
- The policy is toggled on/off or edited → Entra audit-log entry (Identity Protection alerting recommended).

---
[< controls index](README.md) | [< home](../README.md)

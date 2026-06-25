# [37] GuardDuty

**Type:** GuardDuty detector

> **In plain terms —** AWS's managed threat detector. It watches for known-bad behaviour (credential misuse, recon, anomalous API calls) with no rules to write, and pages on anything serious.

## Controls applied

- **Prevention:** —. (Detection only — it doesn't block, it reports.)
- **Detection:** Managed threat detection enabled.
- **Alert:** Findings severity >= 4 → EventBridge → SNS [36].

## What would trigger an alert

- GuardDuty raises a finding of severity ≥ 4 — e.g. credentials used from a Tor exit node, S3 bucket recon, or anomalous API calls → EventBridge → SNS [36].
- An instance or role behaves like compromised credentials (impossible-travel, crypto-mining patterns) → GuardDuty finding → SNS [36].

---
[< controls index](README.md) | [< home](../README.md)

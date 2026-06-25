# [07] SCP (S3 guardrails)

**Type:** Service Control Policy

> **In plain terms —** An org-level rule that forces good S3 hygiene: no plaintext (non-TLS) S3, no PHI upload without KMS encryption, and Block Public Access can't be turned off. Even account admins can't override it.

## Controls applied

- **Prevention:**
  - Deny non-TLS S3
  - deny PHI `PutObject` without SSE-KMS
  - protect account Block-Public-Access. Even account admins cannot override.
- **Detection:** Org CloudTrail on policy changes.
- **Alert:** Policy change → change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- An admin tries to upload PHI without SSE-KMS, or over plain HTTP → request denied → s3-access-denied / unauthorized-api alarm [[35]](35-alarms.md).
- The SCP itself is edited or detached → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).

---
[< controls index](README.md) | [< home](../README.md)

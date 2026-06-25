# [21] S3 de-identified bucket

**Type:** S3 bucket (phi-deident-<acct>)

> **In plain terms —** The Safe-Harbor, de-identified copy of the data. It's readable anywhere in the org for analytics, but is still KMS-encrypted, TLS-only, org-locked, and never public.

## Controls applied

- **Prevention:** Safe-Harbor de-identified copy, readable anywhere in the org; still org-locked (RCP [08]), TLS-only, SSE-KMS [23], Block Public Access on.
- **Detection:** CloudTrail S3 data events.
- **Alert:** Policy change → s3-policy-change alarm [35] + change-alerter [40].

## What would trigger an alert

- The bucket policy or Block Public Access is changed → s3-policy-change alarm [35] + change-alerter [40] → SNS [36].
- A principal outside the org tries to read it → denied by RCP [08] → s3-access-denied alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

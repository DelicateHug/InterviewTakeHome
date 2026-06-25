# [21] S3 de-identified bucket

**Type:** S3 bucket (phi-deident-&lt;acct&gt;)

> **In plain terms —** The Safe-Harbor, de-identified copy of the data. It's readable anywhere in the org for analytics, but is still KMS-encrypted, TLS-only, org-locked, and never public.

## Controls applied

- **Prevention:**
  - Safe-Harbor de-identified copy, readable anywhere in the org
  - still org-locked (RCP [[08]](08-rcp.md)), TLS-only, SSE-KMS [[23]](23-kms-deident.md), Block Public Access on.
- **Detection:** CloudTrail S3 data events.
- **Alert:** Policy change → s3-policy-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- The bucket policy or Block Public Access is changed → s3-policy-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- A principal outside the org tries to read it → denied by RCP [[08]](08-rcp.md) → s3-access-denied alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

# [39] CloudTrail log bucket

**Type:** S3 bucket (ith-cloudtrail-<acct>)

> **In plain terms —** The tamper-resistant store for the trail's log files — KMS-encrypted, never public, TLS-only, and writable only by the CloudTrail service.

## Controls applied

- **Prevention:** SSE-KMS [24]; Block Public Access on; CloudTrail-service write only; TLS-only.
- **Detection:** CloudTrail.
- **Alert:** Policy change → s3-policy-change alarm [35] + change-alerter [40].

## What would trigger an alert

- The bucket policy or Block Public Access is changed (an attempt to expose or tamper with the audit logs) → s3-policy-change alarm [35] + change-alerter [40] → SNS [36].
- A principal other than CloudTrail tries to write or read the logs → AccessDenied → s3-access-denied / unauthorized-api alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

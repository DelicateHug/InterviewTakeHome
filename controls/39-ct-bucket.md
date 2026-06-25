# [39] CloudTrail log bucket

**Type:** S3 bucket (ith-cloudtrail-&lt;acct&gt;)

> **In plain terms —** The tamper-resistant store for the trail's log files — KMS-encrypted, never public, TLS-only, and writable only by the CloudTrail service.

## Controls applied

- **Prevention:**
  - SSE-KMS [[24]](24-kms-logs.md)
  - Block Public Access on
  - CloudTrail-service write only
  - TLS-only.
- **Detection:** CloudTrail.
- **Alert:** Policy change → s3-policy-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- The bucket policy or Block Public Access is changed (an attempt to expose or tamper with the audit logs) → s3-policy-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- A principal other than CloudTrail tries to write or read the logs → AccessDenied → s3-access-denied / unauthorized-api alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

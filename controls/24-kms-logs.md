# [24] Logs / notifications KMS CMK

**Type:** KMS customer-managed key

> **In plain terms —** The key that encrypts the security plumbing — CloudTrail [33], CloudWatch Logs [34], and the SNS alert topic [36]. Disabling it would blind the monitoring, so it is watched closely.

## Controls applied

- **Prevention:** Encrypts CloudTrail [33], CloudWatch Logs [34], and the SNS topic [36].
- **Detection:** CloudTrail kms events.
- **Alert:** DisableKey / ScheduleKeyDeletion → kms-disable-delete alarm [35].

## What would trigger an alert

- Someone disables or schedules deletion of this key — an attempt to blind logging and alerting → kms-disable-delete alarm [35] → SNS [36].
- A principal without a grant tries to use the key → AccessDenied → unauthorized-api alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

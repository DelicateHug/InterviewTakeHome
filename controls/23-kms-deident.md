# [23] De-identified KMS CMK

**Type:** KMS customer-managed key

> **In plain terms —** The single key that encrypts the de-identified bucket [[21]](21-s3-deident.md). Rotation is on.

## Controls applied

- **Prevention:**
  - Encrypts the de-identified bucket [[21]](21-s3-deident.md)
  - rotation on.
- **Detection:** CloudTrail kms events.
- **Alert:** DisableKey / ScheduleKeyDeletion → kms-disable-delete alarm [[35]](35-alarms.md).

## What would trigger an alert

- The key is disabled or scheduled for deletion → kms-disable-delete alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md).
- A principal without a grant tries to use the key → AccessDenied → unauthorized-api alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

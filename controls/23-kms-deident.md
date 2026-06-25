# [23] De-identified KMS CMK

**Type:** KMS customer-managed key

> **In plain terms —** The single key that encrypts the de-identified bucket [21]. Rotation is on.

## Controls applied

- **Prevention:** Encrypts the de-identified bucket [21]; rotation on.
- **Detection:** CloudTrail kms events.
- **Alert:** DisableKey / ScheduleKeyDeletion → kms-disable-delete alarm [35].

## What would trigger an alert

- The key is disabled or scheduled for deletion → kms-disable-delete alarm [35] → SNS [36].
- A principal without a grant tries to use the key → AccessDenied → unauthorized-api alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

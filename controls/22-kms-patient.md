# [22] Per-patient KMS CMKs

**Type:** KMS customer-managed keys (x7)

> **In plain terms —** One encryption key per patient, so each patient's data is sealed under its own key. Disabling a single key instantly cuts access to exactly one patient — a precise response lever during an incident.

## Controls applied

- **Prevention:** One CMK per patient (object encrypted under its patient's key); rotation on; key policy grants only the 4 reader roles `Decrypt`/`GenerateDataKey`. Response lever: disable one key → exactly one patient goes dark.
- **Detection:** CloudTrail kms events; kms-disable-delete filter [34].
- **Alert:** DisableKey / ScheduleKeyDeletion → kms-disable-delete alarm [35].

## What would trigger an alert

- Anyone disables or schedules deletion of a patient key (malicious, or an intended response action) → kms-disable-delete alarm [35] → SNS [36].
- A role not on the key policy tries to `Decrypt` an object → AccessDenied → unauthorized-api alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

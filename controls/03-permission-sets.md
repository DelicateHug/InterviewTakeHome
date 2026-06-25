# [03] Permission sets (3)

**Type:** IAM Identity Center permission sets

> **In plain terms —** The three roles a user can pick at the AWS portal: SuperAdmin (everything), Admin (everything except KMS), and S3Reader (read S3 only from inside the VPC). They decide what each signed-in person can touch.

## Controls applied

- **Prevention:** `ITH-SuperAdmin` (all), `ITH-Admin` (Deny `kms:*`), `ITH-S3Reader` (S3 read only when `aws:sourceVpce` [13]); 1h session; further capped by the account SCP [41].
- **Detection:** CloudTrail logs use and edits.
- **Alert:** Edit → change-alerter [40]; AccessDenied → unauthorized-api alarm [35].

## What would trigger an alert

- Someone edits a permission set — e.g. removes the `Deny kms:*` from the Admin role → change-alerter [40] → SNS [36].
- The Admin role tries a KMS call, or S3Reader is used from outside the VPC → AccessDenied → unauthorized-api alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

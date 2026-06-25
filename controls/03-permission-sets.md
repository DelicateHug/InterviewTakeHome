# [03] Permission sets (3)

**Type:** IAM Identity Center permission sets

> **In plain terms —** The three roles a user can pick at the AWS portal: SuperAdmin (everything, though a permissions boundary [[42]](42-permission-boundary.md) still walls off KMS), Admin (everything except KMS), and S3Reader (read S3 only from inside the VPC). They decide what each signed-in person can touch.

## Controls applied

- **Prevention:**
  - `ITH-SuperAdmin` (all, but capped to everything-except-`kms:*` by a permissions boundary [[42]](42-permission-boundary.md)), `ITH-Admin` (inline Deny `kms:*`), `ITH-S3Reader` (S3 read only when `aws:sourceVpce` [[13]](13-s3-gateway-endpoint.md)) — SuperAdmin and Admin both lose KMS, by **different** mechanisms (boundary ceiling vs explicit deny)
  - 1h session
  - further capped by the account SCP [[41]](41-account-scp.md).
- **Detection:** CloudTrail logs use and edits.
- **Alert:**
  - Edit → change-alerter [[40]](40-change-alerter.md)
  - AccessDenied → unauthorized-api alarm [[35]](35-alarms.md).

## What would trigger an alert

- Someone edits a permission set — e.g. removes the `Deny kms:*` from the Admin role → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- The Admin role tries a KMS call, or S3Reader is used from outside the VPC → AccessDenied → unauthorized-api alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

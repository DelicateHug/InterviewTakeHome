# [32] s3 user role

**Type:** IAM role (the 's3' principal)

> **In plain terms —** The "s3" principal. It can call `GetObject`, but the bucket policy denies it unless the request comes from inside the VPC. Tested both ways: from a laptop it's denied; in-VPC it works.

## Controls applied

- **Prevention:**
  - Can `GetObject`, but the bucket policy denies unless `aws:sourceVpce` matches. Verified: assume from laptop → AccessDenied
  - in-VPC → allowed.
- **Detection:**
  - CloudTrail
  - s3-access-denied filter [[34]](34-log-group.md).
- **Alert:**
  - AccessDenied → s3-access-denied alarm [[35]](35-alarms.md)
  - role change → change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- The role is used from a laptop / anywhere outside the VPC → AccessDenied → s3-access-denied alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md).
- The role's trust policy or permissions are changed → change-alerter [[40]](40-change-alerter.md).

---
[< controls index](README.md) | [< home](../README.md)

# [32] s3 user role

**Type:** IAM role (the 's3' principal)

> **In plain terms —** The "s3" principal. It can call `GetObject`, but the bucket policy denies it unless the request comes from inside the VPC. Tested both ways: from a laptop it's denied; in-VPC it works.

## Controls applied

- **Prevention:** Can `GetObject`, but the bucket policy denies unless `aws:sourceVpce` matches. Verified: assume from laptop → AccessDenied; in-VPC → allowed.
- **Detection:** CloudTrail; s3-access-denied filter [34].
- **Alert:** AccessDenied → s3-access-denied alarm [35]; role change → change-alerter [40].

## What would trigger an alert

- The role is used from a laptop / anywhere outside the VPC → AccessDenied → s3-access-denied alarm [35] → SNS [36].
- The role's trust policy or permissions are changed → change-alerter [40].
- The role is assumed from an IP outside the allow-list → IP-alerter [38].

---
[< controls index](README.md) | [< home](../README.md)

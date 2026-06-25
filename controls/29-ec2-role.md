# [29] EC2 instance role

**Type:** IAM role

> **In plain terms —** The least-privilege role the EC2 app [28] uses to read S3 and decrypt with KMS. Humans never get this directly — only the app does.

## Controls applied

- **Prevention:** Least privilege: S3 read on the buckets + `kms:Decrypt` + SSM core. The app uses this role; humans never get direct S3.
- **Detection:** CloudTrail; iam-policy-change filter [34].
- **Alert:** Role / policy change → iam-policy-change alarm [35] + change-alerter [40].

## What would trigger an alert

- The role's policy is changed, or a new policy is attached to broaden its access → iam-policy-change alarm [35] + change-alerter [40] → SNS [36].
- The role is assumed from an IP outside the allow-list → IP-alerter [38].

---
[< controls index](README.md) | [< home](../README.md)

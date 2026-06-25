# [31] On-prem node role

**Type:** IAM role

> **In plain terms —** The least-privilege role the on-prem job [30] uses: read the sensitive bucket and decrypt, and nothing more.

## Controls applied

- **Prevention:** Least privilege: S3 read on the sensitive bucket + `kms:Decrypt` + SSM core.
- **Detection:** CloudTrail; iam-policy-change filter [34].
- **Alert:** Role / policy change → iam-policy-change alarm [35] + change-alerter [40].

## What would trigger an alert

- The role's policy is changed or broadened → iam-policy-change alarm [35] + change-alerter [40] → SNS [36].
- The role is assumed from an IP outside the allow-list → IP-alerter [38].

---
[< controls index](README.md) | [< home](../README.md)

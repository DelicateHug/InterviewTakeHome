# [35] CloudWatch alarms (9)

**Type:** CloudWatch alarms

> **In plain terms —** The nine tripwires that turn log metrics into pages. Each one maps a specific risky action to a notification. Three of them already fired on real activity during the build.

## Controls applied

- **Prevention:** —. (These are detective controls, not preventive.)
- **Detection:** root-usage, console-no-mfa, unauthorized-api, iam-policy-change, s3-policy-change, kms-disable-delete, cloudtrail-change, sg-change, s3-access-denied.
- **Alert:** Any alarm → SNS [[36]](36-sns.md) (3 already fired on real activity during the build).

## What would trigger an alert

Each alarm watches for one concrete action — all route to SNS [[36]](36-sns.md):

- The **root** user signs in or acts → `root-usage`
- A console login without MFA → `console-no-mfa`
- An API call returns AccessDenied → `unauthorized-api`
- An IAM or bucket policy is edited → `iam-policy-change` / `s3-policy-change`
- A KMS key is disabled or scheduled for deletion → `kms-disable-delete`
- The trail is stopped or altered → `cloudtrail-change`
- A security group is changed → `sg-change`
- A blocked read on the sensitive bucket [[20]](20-s3-sensitive.md) → `s3-access-denied`

---
[< controls index](README.md) | [< home](../README.md)

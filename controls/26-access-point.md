# [26] S3 access point

**Type:** S3 access point

> **In plain terms —** A dedicated front door to the sensitive bucket [[20]](20-s3-sensitive.md) that the Lambda redactor [[27]](27-lambda-redactor.md) reads through, so the bucket can delegate narrow access without opening up its main bucket policy.

## Controls applied

- **Prevention:**
  - Standard access point the redactor [[27]](27-lambda-redactor.md) reads through
  - the bucket policy delegates to same-account access points.
- **Detection:** CloudTrail.
- **Alert:** AP / policy change → change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- The access point or its policy is created, edited, or deleted → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- A principal other than the redactor [[27]](27-lambda-redactor.md) tries to read through it → denied → s3-access-denied alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

# [26] S3 access point

**Type:** S3 access point

> **In plain terms —** A dedicated front door to the sensitive bucket [20] that the Lambda redactor [27] reads through, so the bucket can delegate narrow access without opening up its main bucket policy.

## Controls applied

- **Prevention:** Standard access point the redactor [27] reads through; the bucket policy delegates to same-account access points.
- **Detection:** CloudTrail.
- **Alert:** AP / policy change → change-alerter [40].

## What would trigger an alert

- The access point or its policy is created, edited, or deleted → change-alerter [40] → SNS [36].
- A principal other than the redactor [27] tries to read through it → denied → s3-access-denied alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

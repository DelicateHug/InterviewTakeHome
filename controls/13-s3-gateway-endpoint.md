# [13] S3 gateway endpoint

**Type:** Gateway VPC endpoint

> **In plain terms —** The private door to S3 for things inside the VPC (the EC2 app [[28]](28-ec2-webapp.md) and the s3 user [[32]](32-s3-reader-role.md)). Requests through it carry the VPC-endpoint ID the sensitive bucket requires, which is how the bucket knows the caller is in-VPC.

## Controls applied

- **Prevention:**
  - In-VPC S3 for the EC2 app [[28]](28-ec2-webapp.md) and s3 user [[32]](32-s3-reader-role.md)
  - requests carry `aws:sourceVpce` = this id, satisfying the bucket VPC-lock [[20]](20-s3-sensitive.md).
- **Detection:** CloudTrail.
- **Alert:** Endpoint / policy change → change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- The endpoint or its policy is changed → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- A caller bypasses the endpoint, so the request lacks the right `aws:sourceVpce` and the bucket denies it → s3-access-denied alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

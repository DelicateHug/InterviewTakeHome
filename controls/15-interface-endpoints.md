# [15] SSM / STS / KMS / Logs endpoints

**Type:** Interface VPC endpoints

> **In plain terms —** Private doors for the other AWS services the workloads need (Systems Manager, STS, KMS, CloudWatch Logs), so the VPC never needs any internet access.

## Controls applied

- **Prevention:** ssm, ssmmessages, ec2messages, sts, kms, logs — keep the VPC internet-free; SG-restricted to 443 from the app / on-prem SGs.
- **Detection:** CloudTrail.
- **Alert:** Endpoint / policy change → change-alerter [40].

## What would trigger an alert

- An endpoint or its endpoint policy is changed → change-alerter [40] → SNS [36].
- The endpoints SG [16] that fronts them is modified → sg-change alarm [35] + change-alerter [40].

---
[< controls index](README.md) | [< home](../README.md)

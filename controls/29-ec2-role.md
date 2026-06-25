# [29] EC2 instance role

**Type:** IAM role

> **In plain terms —** The least-privilege role the EC2 app [[28]](28-ec2-webapp.md) uses to read S3 and decrypt with KMS. Humans never get this directly — only the app does.

## Controls applied

- **Prevention:**
  - Least privilege: S3 read on the buckets + `kms:Decrypt` + SSM core. The app uses this role
  - humans never get direct S3.
- **Detection:**
  - CloudTrail
  - iam-policy-change filter [[34]](34-log-group.md).
- **Alert:** Role / policy change → iam-policy-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- The role's policy is changed, or a new policy is attached to broaden its access → iam-policy-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- These EC2 instance-role credentials are used off the instance — from an IP outside AWS, or from another AWS account → GuardDuty `InstanceCredentialExfiltration.OutsideAWS` / `.InsideAWS` [[37]](37-guardduty.md) → SNS [[36]](36-sns.md).

---
[< controls index](README.md) | [< home](../README.md)

# [31] On-prem node role

**Type:** IAM role

> **In plain terms —** The least-privilege role the on-prem job [[30]](30-onprem-node.md) uses: read the sensitive bucket and decrypt, and nothing more.

## Controls applied

- **Prevention:** Least privilege: S3 read on the sensitive bucket + `kms:Decrypt` + SSM core.
- **Detection:**
  - CloudTrail
  - iam-policy-change filter [[34]](34-log-group.md).
- **Alert:** Role / policy change → iam-policy-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- The role's policy is changed or broadened → iam-policy-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- These EC2 instance-role credentials are used off the on-prem node — from an IP outside AWS, or from another AWS account → GuardDuty `InstanceCredentialExfiltration.OutsideAWS` / `.InsideAWS` [[37]](37-guardduty.md) → SNS [[36]](36-sns.md).

---
[< controls index](README.md) | [< home](../README.md)

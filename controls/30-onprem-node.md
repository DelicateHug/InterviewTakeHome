# [30] On-prem k3s node

**Type:** EC2 + k3s (Kubernetes)

> **In plain terms —** The simulated datacenter server. A scheduled k3s job reads S3 across peering through the interface endpoint [[14]](14-s3-interface-endpoint.md); it's SSM-managed with no SSH.

## Controls applied

- **Prevention:**
  - Single-node k3s
  - a CronJob reads S3 across peering via the interface endpoint [[14]](14-s3-interface-endpoint.md)
  - IMDS hop-limit 2
  - SSM-managed (no SSH).
- **Detection:**
  - CloudTrail
  - SSM session logging.
- **Alert:** Instance / SG change → change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- The instance or its SG [[18]](18-onprem-sg.md) is changed → change-alerter [[40]](40-change-alerter.md) / sg-change alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md).
- Its role [[31]](31-onprem-role.md) credentials are used off this instance — from an IP outside AWS, or from another AWS account → GuardDuty `InstanceCredentialExfiltration` [[37]](37-guardduty.md) → SNS [[36]](36-sns.md).

---
[< controls index](README.md) | [< home](../README.md)

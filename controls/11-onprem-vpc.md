# [11] On-prem VPC

**Type:** VPC 192.168.0.0/16

> **In plain terms —** A stand-in for the company datacenter. It can reach the PHI data only over the peering link [[12]](12-peering.md) and the private S3 interface endpoint [[14]](14-s3-interface-endpoint.md).

## Controls applied

- **Prevention:**
  - Simulated datacenter
  - reaches the data tier only via peering [[12]](12-peering.md) + the S3 interface endpoint [[14]](14-s3-interface-endpoint.md).
- **Detection:** CloudTrail.
- **Alert:** Network change → change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- An admin changes a route, or edits/creates the peering attachment to reach the data tier a new way → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- The on-prem node SG [[18]](18-onprem-sg.md) is modified → sg-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md).

---
[< controls index](README.md) | [< home](../README.md)

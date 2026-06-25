# [18] On-prem node security group

**Type:** Security group

> **In plain terms —** The firewall on the on-prem k3s node [[30]](30-onprem-node.md). No inbound (SSM only); outbound to the internet for k3s plus the private S3 interface endpoint.

## Controls applied

- **Prevention:**
  - No inbound (SSM only)
  - egress to internet (k3s) + the S3 interface endpoint.
- **Detection:**
  - CloudTrail
  - sg-change filter [[34]](34-log-group.md).
- **Alert:** SG change → sg-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- An inbound rule is opened on the node (e.g. SSH from anywhere) → sg-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- Egress rules are changed → sg-change alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

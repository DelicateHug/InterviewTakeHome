# [18] On-prem node security group

**Type:** Security group

> **In plain terms —** The firewall on the on-prem k3s node [30]. No inbound (SSM only); outbound to the internet for k3s plus the private S3 interface endpoint.

## Controls applied

- **Prevention:** No inbound (SSM only); egress to internet (k3s) + the S3 interface endpoint.
- **Detection:** CloudTrail; sg-change filter [34].
- **Alert:** SG change → sg-change alarm [35] + change-alerter [40].

## What would trigger an alert

- An inbound rule is opened on the node (e.g. SSH from anywhere) → sg-change alarm [35] + change-alerter [40] → SNS [36].
- Egress rules are changed → sg-change alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

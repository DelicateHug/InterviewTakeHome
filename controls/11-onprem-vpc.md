# [11] On-prem VPC

**Type:** VPC 192.168.0.0/16

> **In plain terms —** A stand-in for the company datacenter. It can reach the PHI data only over the peering link [12] and the private S3 interface endpoint [14].

## Controls applied

- **Prevention:** Simulated datacenter; reaches the data tier only via peering [12] + the S3 interface endpoint [14].
- **Detection:** CloudTrail.
- **Alert:** Network change → change-alerter [40].

## What would trigger an alert

- An admin changes a route, or edits/creates the peering attachment to reach the data tier a new way → change-alerter [40] → SNS [36].
- The on-prem node SG [18] is modified → sg-change alarm [35] + change-alerter [40].

---
[< controls index](README.md) | [< home](../README.md)

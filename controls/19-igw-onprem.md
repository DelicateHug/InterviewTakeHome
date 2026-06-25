# [19] On-prem internet gateway

**Type:** Internet gateway

> **In plain terms —** The internet exit for the on-prem network only. PHI reads still take the private route via the interface endpoint; this is just ordinary datacenter egress.

## Controls applied

- **Prevention:**
  - Datacenter egress for the on-prem VPC only
  - PHI reads still go private via the interface endpoint over peering.
- **Detection:** CloudTrail.
- **Alert:** Change → change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- The IGW is detached, deleted, or a route to it is changed → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- An IGW is attached to the **workload** VPC [[10]](10-workload-vpc.md) (which should never have one) → change-alerter [[40]](40-change-alerter.md).

---
[< controls index](README.md) | [< home](../README.md)

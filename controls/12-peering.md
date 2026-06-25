# [12] VPC peering

**Type:** VPC peering connection

> **In plain terms —** The private link between the on-prem network and the workload network. It's wired so on-prem must use the interface endpoint [[14]](14-s3-interface-endpoint.md) — gateway endpoints deliberately don't work across peering.

## Controls applied

- **Prevention:**
  - Routes both ways between [[10]](10-workload-vpc.md) and [[11]](11-onprem-vpc.md)
  - gateway endpoints are NOT reachable across peering (forces the interface endpoint). Tradeoff: non-transitive & N^2
  - TGW is the successor.
- **Detection:** CloudTrail on peering changes.
- **Alert:** Peering change → change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- An admin edits the peering connection or its route tables (e.g. widening what on-prem can reach) → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- A new peering connection is created or accepted → change-alerter [[40]](40-change-alerter.md).

---
[< controls index](README.md) | [< home](../README.md)

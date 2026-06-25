# [12] VPC peering

**Type:** VPC peering connection

> **In plain terms —** The private link between the on-prem network and the workload network. It's wired so on-prem must use the interface endpoint [14] — gateway endpoints deliberately don't work across peering.

## Controls applied

- **Prevention:** Routes both ways between [10] and [11]; gateway endpoints are NOT reachable across peering (forces the interface endpoint). Tradeoff: non-transitive & N^2; TGW is the successor.
- **Detection:** CloudTrail on peering changes.
- **Alert:** Peering change → change-alerter [40].

## What would trigger an alert

- An admin edits the peering connection or its route tables (e.g. widening what on-prem can reach) → change-alerter [40] → SNS [36].
- A new peering connection is created or accepted → change-alerter [40].

---
[< controls index](README.md) | [< home](../README.md)

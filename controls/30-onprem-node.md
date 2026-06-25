# [30] On-prem k3s node

**Type:** EC2 + k3s (Kubernetes)

> **In plain terms —** The simulated datacenter server. A scheduled k3s job reads S3 across peering through the interface endpoint [14]; it's SSM-managed with no SSH.

## Controls applied

- **Prevention:** Single-node k3s; a CronJob reads S3 across peering via the interface endpoint [14]; IMDS hop-limit 2; SSM-managed (no SSH).
- **Detection:** CloudTrail; SSM session logging.
- **Alert:** Instance / SG change → change-alerter [40].

## What would trigger an alert

- The instance or its SG [18] is changed → change-alerter [40] / sg-change alarm [35] → SNS [36].
- Its role [31] is assumed from an unexpected IP → IP-alerter [38].

---
[< controls index](README.md) | [< home](../README.md)

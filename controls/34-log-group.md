# [34] CloudWatch Logs + metric filters

**Type:** Log group + 11 metric filters

> **In plain terms —** Where the trail's logs land and get scanned. Eleven pattern filters turn "this risky thing happened" log lines into metrics the alarms watch — including global IAM events, regardless of region.

## Controls applied

- **Prevention:** Trail log group `/ith/cloudtrail`, KMS-encrypted (aggregates multi-region + global IAM events).
- **Detection:** 11 metric filters (9 baseline + 2 exclusion-based [40]) turn log patterns into metrics.
- **Alert:** Metrics feed the alarms [35].

## What would trigger an alert

- Any watched pattern shows up in the logs (root use, policy change, denied access, SG change, …) → the matching alarm [35] fires → SNS [36].
- The log group or one of its metric filters is deleted or edited → change-alerter [40].

---
[< controls index](README.md) | [< home](../README.md)

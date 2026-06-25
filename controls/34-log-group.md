# [34] CloudWatch Logs + metric filters

**Type:** Log group + 12 metric filters

> **In plain terms —** Where the trail's logs land and get scanned. Twelve pattern filters turn "this risky thing happened" log lines into metrics the alarms watch — including global IAM events, regardless of region.

## Controls applied

- **Prevention:** Trail log group `/ith/cloudtrail`, KMS-encrypted (aggregates multi-region + global IAM events).
- **Detection:** 12 metric filters (9 baseline + 3 exclusion-based [[40]](40-change-alerter.md)[[60]](60-protect-detection.md)) turn log patterns into metrics.
- **Alert:** Metrics feed the alarms [[35]](35-alarms.md).

## What would trigger an alert

- Any watched pattern shows up in the logs (root use, policy change, denied access, SG change, …) → the matching alarm [[35]](35-alarms.md) fires → SNS [[36]](36-sns.md).
- The log group or one of its metric filters is deleted or edited → change-alerter [[40]](40-change-alerter.md).

---
[< controls index](README.md) | [< home](../README.md)

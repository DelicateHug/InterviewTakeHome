# [33] CloudTrail

**Type:** CloudTrail trail (ith-trail)

> **In plain terms —** The account's flight recorder. It logs every API call across all regions, validates the log files so tampering shows, and feeds both the log bucket [39] and CloudWatch [34]. Nearly every alarm depends on it.

## Controls applied

- **Prevention:** Multi-region; log-file validation; KMS-encrypted [24]; management + S3 data events; → log bucket [39] + CloudWatch Logs [34].
- **Detection:** This is the primary detection source for the whole account.
- **Alert:** StopLogging / DeleteTrail / UpdateTrail → cloudtrail-change alarm [35].

## What would trigger an alert

- Anyone stops, deletes, or reconfigures the trail to "go dark" → cloudtrail-change alarm [35] → SNS [36].
- The trail's KMS key [24] is disabled → kms-disable-delete alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

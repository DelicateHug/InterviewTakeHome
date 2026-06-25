# [33] CloudTrail

**Type:** CloudTrail trail (ith-trail)

> **In plain terms —** The account's flight recorder. It logs every API call across all regions, validates the log files so tampering shows, and feeds both the log bucket [[39]](39-ct-bucket.md) and CloudWatch [[34]](34-log-group.md). Nearly every alarm depends on it.

## Controls applied

- **Prevention:**
  - Multi-region
  - log-file validation
  - KMS-encrypted [[24]](24-kms-logs.md)
  - management + S3 data events
  - → log bucket [[39]](39-ct-bucket.md) + CloudWatch Logs [[34]](34-log-group.md).
- **Detection:** This is the primary detection source for the whole account.
- **Alert:** StopLogging / DeleteTrail / UpdateTrail → cloudtrail-change alarm [[35]](35-alarms.md).

## What would trigger an alert

- Anyone stops, deletes, or reconfigures the trail to "go dark" → cloudtrail-change alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md).
- The trail's KMS key [[24]](24-kms-logs.md) is disabled → kms-disable-delete alarm [[35]](35-alarms.md).

> **Why the S3 data events matter (and what depends on them).** The `s3-access-denied`
> alarm [[35]](35-alarms.md) only sees object-level reads/denials because this trail has
> **S3 data (object-level) events** turned on. A `GetObject` 403 is a *data* event, not a
> management event — data events are OFF by default and billed separately, so dropping them
> to save cost would silently blind that alarm (it would never fire and would look healthy).
> For PHI this is also a HIPAA audit-trail requirement (45 CFR §164.312(b)). The alarm
> itself is count-only: to learn **who/what/how**, pivot to the `/ith/cloudtrail` log group
> [[34]](34-log-group.md) and query the alarm's time window (`userIdentity.arn`,
> `sourceIPAddress`, `requestParameters.key`).

---
[< controls index](README.md) | [< home](../README.md)

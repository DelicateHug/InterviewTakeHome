# [08] RCP (deny S3 outside org)

**Type:** Resource Control Policy

> **In plain terms —** A resource-side org rule that denies all S3 access to any principal outside this organization — a backstop in case a bucket policy is ever misconfigured.

## Controls applied

- **Prevention:** Resource-side deny of `s3:*` when `aws:PrincipalOrgID` != this org (AWS services excluded). Stops external / confused-deputy access even if a bucket policy were mis-set.
- **Detection:** Org CloudTrail on policy changes.
- **Alert:** Policy change → change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- A principal from another AWS account (or the public) tries to read a bucket → denied by the RCP → s3-access-denied alarm [[35]](35-alarms.md).
- The RCP is edited or detached → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).

---
[< controls index](README.md) | [< home](../README.md)

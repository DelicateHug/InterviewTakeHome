# [41] Strict account allow-list SCP

**Type:** Service Control Policy

> **In plain terms —** The account's hard ceiling. It denies every AWS service except the handful this demo needs, and caps even SuperAdmin — so a compromised admin still can't reach unused services.

## Controls applied

- **Prevention:** Denies **all** actions except the services this demo needs (s3, kms, ec2, lambda, ssm + messages, sts, iam, cloudtrail, guardduty, cloudwatch, logs, sns, events, tag). Attached to the account [09]; caps even SuperAdmin.
- **Detection:** Org CloudTrail on policy changes.
- **Alert:** Policy change → change-alerter [40].

## What would trigger an alert

- Any user — even SuperAdmin — calls a service outside the allow-list → denied → unauthorized-api alarm [35] → SNS [36].
- The SCP is edited or detached (an attempt to lift the ceiling) → change-alerter [40].

---
[< controls index](README.md) | [< home](../README.md)

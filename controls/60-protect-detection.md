# [60] Detection self-protection

**Type:** Service Control Policy + CloudWatch alarm

> **In plain terms —** Who watches the watchers. Detection you can silently delete isn't detection — so this both *blocks* anyone but the deploy pipeline from touching the alarms / trail / GuardDuty (an SCP), and *alerts* if a change ever slips through anyway (a metric filter). Prevent **and** detect.

## Controls applied

- **Prevention:** The `ith-scp-protect-detection` SCP (00-org) **Denies** every principal in the account *except* the IaC deploy role from mutating the detection stack — `cloudwatch:DeleteAlarms`/`PutMetricAlarm`/`DisableAlarmActions`, `logs:Delete|PutMetricFilter`/`DeleteLogGroup`, `sns:DeleteTopic`/`SetTopicAttributes`, `events:Delete|DisableRule`, `guardduty:Delete|UpdateDetector`, `cloudtrail:StopLogging`/`DeleteTrail`. Deny wins over the allow-list SCP [[41]](41-account-scp.md), so it caps even SuperAdmin; break-glass stays via the management account's `OrganizationAccountAccessRole`.
- **Detection:** The `ith-detection-tampering` metric filter [[34]](34-log-group.md) + alarm [[35]](35-alarms.md) fire on those same mutating events, excluding **only** the deploy role — a *narrower* list than the change-alerter [[40]](40-change-alerter.md), so even a SuperAdmin change is caught if it ever bypasses the SCP.
- **Alert:** Tamper event → `ith-detection-tampering` alarm → SNS [[36]](36-sns.md).

## What would trigger an alert

- A non-deploy principal (SuperAdmin, the Admin role, or stolen credentials) deletes an alarm, drops a metric filter, mutes the SNS topic, disables an EventBridge rule, stops CloudTrail, or disables GuardDuty → the protect-detection SCP **denies** the call (→ AccessDenied → unauthorized-api alarm [[35]](35-alarms.md)); if the SCP is ever detached or the actor is added to the exempt list, the **detection-tampering** alarm [[35]](35-alarms.md) pages on the successful mutation → SNS [[36]](36-sns.md).
- The SCP itself is edited or detached (an attempt to lift the lock) → org CloudTrail → change-alerter [[40]](40-change-alerter.md).

> **Single-purpose vs shared accounts —** Here the only cloudwatch / logs / sns / events / guardduty resources *are* the detection stack, so a blanket action-deny is exact and needs no resource tags. In a shared account, gate the same actions on `aws:ResourceTag/<protect>=detection` **and** also deny `TagResource`/`UntagResource` of that tag key — otherwise an attacker untags the resource first, then mutates it.

---
[< controls index](README.md) | [< home](../README.md)

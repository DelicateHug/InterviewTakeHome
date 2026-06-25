# [36] SNS security alerts

**Type:** SNS topic

> **In plain terms —** The notification pipe. Every alarm, GuardDuty finding, and custom alerter publishes here, and it emails the security contact once they confirm the subscription. Encrypted in transit and at rest.

## Controls applied

- **Prevention:**
  - KMS-encrypted topic
  - publishers restricted to CloudWatch + EventBridge + the account.
- **Detection:** —. (This is the delivery channel, not a detector.)
- **Alert:** Delivery channel for all alarms [[35]](35-alarms.md) + GuardDuty [[37]](37-guardduty.md) + change-alerter [[40]](40-change-alerter.md) (email must be confirmed).

## What would trigger an alert

- Any alarm [[35]](35-alarms.md), GuardDuty [[37]](37-guardduty.md), or change-alerter [[40]](40-change-alerter.md) fires → a message is published here and emailed to the security contact.
- A principal not on the topic policy tries to publish to or modify the topic → AccessDenied → unauthorized-api alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

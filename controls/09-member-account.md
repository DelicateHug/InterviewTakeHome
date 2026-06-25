# [09] Member account ith-workload

**Type:** AWS account

> **In plain terms —** The single dedicated AWS account where everything in this demo actually runs. Isolating it keeps the blast radius small, and the allow-list SCP [[41]](41-account-scp.md) caps what it can do.

## Controls applied

- **Prevention:**
  - Account `118821711925`: dedicated blast radius
  - the strict allow-list SCP [[41]](41-account-scp.md) caps it to demo-only services
  - `close_on_deletion=true`.
- **Detection:** Account CloudTrail [[33]](33-cloudtrail.md).
- **Alert:** See per-resource alerts + change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- Any mutating action in the account by a non-excluded user (stolen creds, a curious admin) → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- The account's **root** user is used → root-usage alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

# [05] Management account

**Type:** AWS Organizations mgmt acct

> **In plain terms —** The top of the AWS Organization. It owns the org-wide guardrails and Identity Center and is the only account allowed to assume into the workload account [[09]](09-member-account.md). It deliberately holds nothing sensitive.

## Controls applied

- **Prevention:**
  - Org root with SCP + RCP enabled
  - holds Identity Center
  - assumes OrganizationAccountAccessRole into [[09]](09-member-account.md). Not subject to SCPs, so the workload is isolated in a member account.
- **Detection:**
  - Org CloudTrail
  - root-usage metric filter [[34]](34-log-group.md).
- **Alert:** Any root use → root-usage alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md).

## What would trigger an alert

- Anyone signs in as, or takes any action with, the **root** user of this account → root-usage alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md).
- An org SCP / RCP or the OU is changed from here → change-alerter [[40]](40-change-alerter.md).

---
[< controls index](README.md) | [< home](../README.md)

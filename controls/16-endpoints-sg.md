# [16] Endpoints security group

**Type:** Security group

> **In plain terms —** The firewall on the VPC-endpoint doors. It allows HTTPS only from the app SG [[17]](17-app-sg.md) and the on-prem node SG [[18]](18-onprem-sg.md) — addressed by security group, never by IP range.

## Controls applied

- **Prevention:** Ingress 443 from the app SG [[17]](17-app-sg.md) and the on-prem node SG [[18]](18-onprem-sg.md) — SG-as-source, no CIDR.
- **Detection:**
  - CloudTrail
  - sg-change metric filter [[34]](34-log-group.md).
- **Alert:** SG change → sg-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- Someone widens ingress — e.g. adds a `0.0.0.0/0` CIDR or a new port to the endpoints → sg-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- Any rule is added or removed on the SG → sg-change alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

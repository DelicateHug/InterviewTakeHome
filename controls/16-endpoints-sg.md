# [16] Endpoints security group

**Type:** Security group

> **In plain terms —** The firewall on the VPC-endpoint doors. It allows HTTPS only from the app SG [17] and the on-prem node SG [18] — addressed by security group, never by IP range.

## Controls applied

- **Prevention:** Ingress 443 from the app SG [17] and the on-prem node SG [18] — SG-as-source, no CIDR.
- **Detection:** CloudTrail; sg-change metric filter [34].
- **Alert:** SG change → sg-change alarm [35] + change-alerter [40].

## What would trigger an alert

- Someone widens ingress — e.g. adds a `0.0.0.0/0` CIDR or a new port to the endpoints → sg-change alarm [35] + change-alerter [40] → SNS [36].
- Any rule is added or removed on the SG → sg-change alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

# [17] App security group

**Type:** Security group

> **In plain terms —** The firewall on the EC2 web app [28]. No inbound at all (you reach it only via SSM port-forward); outbound is limited to the endpoints SG and the S3 gateway.

## Controls applied

- **Prevention:** No inbound (reached only via SSM port-forward); egress 443 to the endpoints SG [16] + S3 gateway prefix list.
- **Detection:** CloudTrail; sg-change filter [34].
- **Alert:** SG change → sg-change alarm [35] + change-alerter [40].

## What would trigger an alert

- An inbound rule is added — e.g. someone opens SSH/22 or 443 to the app → sg-change alarm [35] + change-alerter [40] → SNS [36].
- Egress is widened beyond the endpoints / S3 → sg-change alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

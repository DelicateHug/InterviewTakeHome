# [17] App security group

**Type:** Security group

> **In plain terms —** The firewall on the EC2 web app [[28]](28-ec2-webapp.md). No inbound at all (you reach it only via SSM port-forward); outbound is limited to the endpoints SG and the S3 gateway.

## Controls applied

- **Prevention:**
  - No inbound (reached only via SSM port-forward)
  - egress 443 to the endpoints SG [[16]](16-endpoints-sg.md) + S3 gateway prefix list.
- **Detection:**
  - CloudTrail
  - sg-change filter [[34]](34-log-group.md).
- **Alert:** SG change → sg-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- An inbound rule is added — e.g. someone opens SSH/22 or 443 to the app → sg-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- Egress is widened beyond the endpoints / S3 → sg-change alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

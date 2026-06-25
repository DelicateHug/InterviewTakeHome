# [16] Endpoints security group

- **Type:** Security group
- **Requirements:** R17

## Controls applied

- Ingress 443 **from the app SG [17]** (SG-as-source, not CIDR).
- Ingress 443 **from the on-prem node SG [18]** (cross-VPC SG reference over peering).

---
[< controls index](README.md) | [< home](../README.md)

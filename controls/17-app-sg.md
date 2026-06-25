# [17] App security group

- **Type:** Security group
- **Requirements:** R17
- **Path:** P3

## Controls applied

- **No inbound** - the web app is reached only via SSM port-forward.
- Egress 443 to the endpoints SG [16] and to the S3 gateway prefix list.

---
[< controls index](README.md) | [< home](../README.md)

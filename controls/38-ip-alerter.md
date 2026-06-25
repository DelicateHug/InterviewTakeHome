# [38] Role-assumption IP alerter

- **Type:** EventBridge + Lambda
- **Requirements:** R12

## Controls applied

- EventBridge on `sts:AssumeRole*` -> Lambda checks source IP vs allow-list -> SNS.
- Alerts on any external IP outside the allow-list (empty default = alert-all for the demo).

---
[< controls index](README.md) | [< home](../README.md)

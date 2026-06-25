# [30] On-prem k3s node

- **Type:** EC2 + k3s (Kubernetes)
- **Requirements:** R16
- **Path:** P2

## Controls applied

- Single-node k3s; a CronJob reads S3 across peering via the interface endpoint [14].
- Pod uses the node role [31] via IMDS (hop limit 2); SSM-managed (no SSH).

---
[< controls index](README.md) | [< home](../README.md)

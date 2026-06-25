# [19] On-prem internet gateway

- **Type:** Internet gateway
- **Requirements:** R16
- **Path:** P2

## Controls applied

- Datacenter egress for the on-prem VPC (k3s installer, image pulls).
- PHI reads still go private via the interface endpoint over peering.

---
[< controls index](README.md) | [< home](../README.md)

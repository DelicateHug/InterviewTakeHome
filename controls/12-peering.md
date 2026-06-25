# [12] VPC peering

- **Type:** VPC peering connection
- **Requirements:** R16
- **Path:** P2

## Controls applied

- Routes both ways between [10] and [11].
- **Tradeoff:** peering is non-transitive & N^2; Transit Gateway is the scalable successor.
- Gateway endpoints are NOT reachable across peering -> on-prem must use the interface endpoint.

---
[< controls index](README.md) | [< home](../README.md)

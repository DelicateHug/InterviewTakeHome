# [14] S3 interface endpoint

- **Type:** Interface VPC endpoint
- **Requirements:** R16
- **Path:** P2

## Controls applied

- PrivateLink S3 reachable across the peering by the on-prem node.
- Private DNS disabled (so it doesn't shadow the gateway endpoint in-VPC).
- Use the `bucket.vpce-...` TLS name for SAN match.

---
[< controls index](README.md) | [< home](../README.md)

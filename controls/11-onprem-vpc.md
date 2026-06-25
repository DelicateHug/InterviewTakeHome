# [11] On-prem VPC

- **Type:** VPC 192.168.0.0/16
- **Requirements:** R16
- **Path:** P2

## Controls applied

- Represents an on-prem datacenter; has an IGW [19] for egress (k3s install).
- Reaches the data tier only via peering [12] + the S3 interface endpoint [14].

---
[< controls index](README.md) | [< home](../README.md)

# [13] S3 gateway endpoint

- **Type:** Gateway VPC endpoint
- **Requirements:** R16
- **Path:** P3,P4

## Controls applied

- Route-table endpoint for in-VPC S3 (EC2 web app, s3-reader).
- Requests carry `aws:sourceVpce` = this id -> satisfies the bucket VPC-lock.

---
[< controls index](README.md) | [< home](../README.md)

# [29] EC2 instance role

- **Type:** IAM role
- **Requirements:** R13
- **Path:** P3

## Controls applied

- Least privilege: S3 read on the buckets + `kms:Decrypt` + SSM core.
- The web app uses this role; humans never get direct S3 (C1).

---
[< controls index](README.md) | [< home](../README.md)

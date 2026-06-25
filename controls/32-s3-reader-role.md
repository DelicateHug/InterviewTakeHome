# [32] s3 user role

- **Type:** IAM role (the 's3' principal)
- **Requirements:** R13
- **Path:** P4

## Controls applied

- Can `GetObject`, but the bucket policy denies unless `aws:sourceVpce` matches.
- Verified: assume from laptop -> AccessDenied; in-VPC -> allowed.

---
[< controls index](README.md) | [< home](../README.md)

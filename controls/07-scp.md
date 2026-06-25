# [07] SCP - S3 guardrails

- **Type:** Service Control Policy
- **Requirements:** R8

## Controls applied

- Deny all S3 when `aws:SecureTransport=false` (TLS required).
- Deny `PutObject` to `phi-*` without `x-amz-server-side-encryption=aws:kms`.
- Deny `PutObject` to `phi-*` when the SSE header is absent.
- Deny `PutAccountPublicAccessBlock` except the deploy role.

---
[< controls index](README.md) | [< home](../README.md)

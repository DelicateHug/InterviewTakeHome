# [20] S3 sensitive bucket

- **Type:** S3 bucket (phi-sensitive-<acct>)
- **Requirements:** R1,R7,C1
- **Path:** P1,P2,P3,P4

## Controls applied

- Holds tokenized ePHI; per-patient SSE-KMS [22]; versioning; Block Public Access on.
- Bucket policy: deny non-TLS; deny outside-org; **deny reads unless `aws:sourceVpce` [13]/[14] or via access point [27]**.
- Effect: humans on a laptop are denied -> must use the EC2 UI [28] (C1). Deploy role exempted for management.
- Account-id suffix naming (R7).

---
[< controls index](README.md) | [< home](../README.md)

# [08] RCP - deny S3 outside org

- **Type:** Resource Control Policy
- **Requirements:** R9

## Controls applied

- Deny `s3:*` when `aws:PrincipalOrgID != o-ncxqr8pp2c` (resource-side).
- Excludes AWS service principals (`aws:PrincipalIsAWSService`).
- Stops confused-deputy / cross-account access even if a bucket policy were mis-set.

---
[< controls index](README.md) | [< home](../README.md)

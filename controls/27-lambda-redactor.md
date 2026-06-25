# [27] Lambda redactor (basic reader)

- **Type:** Lambda + IAM Function URL
- **Requirements:** R16,C2
- **Path:** P1

## Controls applied

- Reads via the access point [26], strips all identifiers, returns **non-sensitive only**.
- IAM-auth Function URL = the 'access point' the basic reader calls.
- Substitute for S3 Object Lambda (AWS-gated for new accounts) - same outcome.

---
[< controls index](README.md) | [< home](../README.md)

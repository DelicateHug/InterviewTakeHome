# [28] EC2 web app

- **Type:** EC2 instance (the human read path)
- **Requirements:** R16,C1,C3
- **Path:** P3

## Controls applied

- **Only** human read path; all 3 admins read details here.
- **SSM-only**: no key pair, no SSH, no public IP; IMDSv2 required.
- Pure-stdlib SigV4 app (no pip/boto3) on :8080; reads via gateway endpoint [13].
- Identifiers stay tokenized even in the UI.

---
[< controls index](README.md) | [< home](../README.md)

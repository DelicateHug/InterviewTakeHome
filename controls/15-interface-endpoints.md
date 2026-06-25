# [15] SSM / STS / KMS / Logs endpoints

- **Type:** Interface VPC endpoints
- **Requirements:** R16

## Controls applied

- ssm, ssmmessages, ec2messages (Session Manager), sts, kms, logs.
- Keep the workload VPC internet-free; SG-restricted to 443 from app/on-prem SGs.
- Note: a missing endpoint silently falls back to public - all are provisioned.

---
[< controls index](README.md) | [< home](../README.md)

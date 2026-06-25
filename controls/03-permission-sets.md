# [03] Permission sets (3)

- **Type:** IAM Identity Center permission sets
- **Requirements:** R13,C1

## Controls applied

- `ITH-SuperAdmin`: AdministratorAccess (all, incl. KMS).
- `ITH-Admin`: relevant services, **explicit `Deny kms:*`**.
- `ITH-S3Reader`: S3 read on the PHI buckets **only when `aws:sourceVpce`** matches [13].
- Created for real (inert until assigned); 1h session.

---
[< controls index](README.md) | [< home](../README.md)

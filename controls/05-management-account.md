# [05] Management account

- **Type:** AWS Organizations mgmt acct
- **Requirements:** R6

## Controls applied

- Org `o-ncxqr8pp2c`; both SCP and RCP policy types enabled on root.
- Holds Identity Center; assumes OrganizationAccountAccessRole into [09] to deploy.
- Not subject to SCPs (AWS rule) - workload isolated in a member account instead.

---
[< controls index](README.md) | [< home](../README.md)

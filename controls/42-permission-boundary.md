# [42] SuperAdmin permissions boundary

**Type:** IAM permissions boundary (customer-managed)

> **In plain terms —** A hard ceiling on what the top admin can ever do. Even though `ITH-SuperAdmin`'s permission set says "allow everything", this boundary caps the *effective* permissions to everything-except-KMS — so SuperAdmin simply cannot touch the patient keys, by a different mechanism than the org SCP [[41]](41-account-scp.md) or Admin's explicit deny [[03]](03-permission-sets.md).

## Controls applied

- **Prevention:** Caps the **maximum** permissions of the `ITH-SuperAdmin` SSO role to *everything except* `kms:*`. The boundary's allowed set is a `NotAction kms:*` **ceiling with no Deny statement**: effective = AdministratorAccess (`Allow *`) ∩ boundary, so KMS is denied simply by sitting **outside** the ceiling. This is the property unique to a permissions boundary — a third, distinct layer alongside the org SCP [[41]](41-account-scp.md) and ITH-Admin's inline `Deny kms:*` [[03]](03-permission-sets.md) (same outcome, three different mechanisms). The customer-managed policy lives in the member account [[09]](09-member-account.md); Identity Center references it by name. Break-glass KMS stays available via the management account's `OrganizationAccountAccessRole`.
- **Detection:**
  - CloudTrail (mgmt/org) on permission-set + boundary attach/detach
  - member-account AccessDenied on any SuperAdmin `kms:*` call.
- **Alert:**
  - SuperAdmin KMS attempt → AccessDenied → unauthorized-api alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md)
  - boundary detach/edit (ceiling lifted) is an org-level change captured by CloudTrail.

## What would trigger an alert

- `ITH-SuperAdmin` tries any `kms:*` action (list, decrypt, disable…) → AccessDenied by the boundary ceiling → unauthorized-api alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md).
- Someone detaches or edits the boundary to lift the KMS ceiling → org-level change captured by CloudTrail → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).

---
[< controls index](README.md) | [< home](../README.md)

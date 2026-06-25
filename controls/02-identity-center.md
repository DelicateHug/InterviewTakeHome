# [02] AWS IAM Identity Center

**Type:** SSO / federation

> **In plain terms —** The AWS-side single sign-on hub. It takes the identity from Entra and hands out account access through permission sets [[03]](03-permission-sets.md) — there are no local AWS passwords.

## Controls applied

- **Prevention:**
  - Single sign-in portal
  - identity source = Entra via SCIM (no local passwords)
  - access only through permission sets [[03]](03-permission-sets.md).
- **Detection:** CloudTrail [[33]](33-cloudtrail.md) logs assignment + permission-set changes.
- **Alert:** Assignment / permission-set change → change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- An admin creates or edits an account assignment, granting a user new access → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- A signed-in user calls something their permission set doesn't allow → AccessDenied → unauthorized-api alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

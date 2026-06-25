# [40] Change / CreateUser alerter

**Type:** CloudWatch metric filters + alarms (2)

> **In plain terms —** A catch-all detector. Two filters on the trail watch for (a) any change-making API call and (b) creating an IAM user — but they only page when the actor *isn't* on the trusted exclusion list (SuperAdmin [03] + the deploy role).

## Controls applied

- **Prevention:** — (detective / responsive).
- **Detection:** Two metric filters on the trail log group [34]: `iam:CreateUser`, and any mutating event (`readOnly=false`). Reads from CloudWatch Logs so global IAM events are caught regardless of region.
- **Alert:** Fires only when the actor is **not on the exclusion list** (default: SuperAdmin [03] + the deploy role) → alarm → SNS [36]; CreateUser has its own named alarm.

## What would trigger an alert

- A non-excluded actor (the Admin role, or stolen credentials) makes any mutating change — edits a policy, SG, route, bucket, etc. → change-alerter → SNS [36].
- Anyone creates an IAM user → dedicated CreateUser alarm → SNS [36].

---
[< controls index](README.md) | [< home](../README.md)

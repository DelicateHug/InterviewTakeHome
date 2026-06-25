# [40] Change / CreateUser alerter

**Type:** CloudWatch metric filters + alarms (3)

> **In plain terms —** A catch-all detector. Three filters on the trail watch for (a) any change-making API call, (b) creating an IAM user, and (c) tampering with the detection stack itself ([[60]](60-protect-detection.md)) — but they only page when the actor *isn't* on the trusted exclusion list (SuperAdmin [[03]](03-permission-sets.md) + the deploy role; the detection-tampering filter excludes the deploy role *only*).

## Controls applied

- **Prevention:** — (detective / responsive).
- **Detection:** Three metric filters on the trail log group [[34]](34-log-group.md): `iam:CreateUser`, any mutating event (`readOnly=false`), and **detection-tampering** — mutations of the detection stack itself (see [[60]](60-protect-detection.md)). Reads from CloudWatch Logs so global IAM events are caught regardless of region.
- **Alert:**
  - Fires only when the actor is **not on the exclusion list** (default: SuperAdmin [[03]](03-permission-sets.md) + the deploy role) → alarm → SNS [[36]](36-sns.md)
  - CreateUser and detection-tampering each have their own named alarm.

## What would trigger an alert

- A non-excluded actor (the Admin role, or stolen credentials) makes any mutating change — edits a policy, SG, route, bucket, etc. → change-alerter → SNS [[36]](36-sns.md).
- Anyone creates an IAM user → dedicated CreateUser alarm → SNS [[36]](36-sns.md).
- Anyone but the deploy role mutates the detection stack (deletes an alarm, drops a filter, mutes SNS, stops the trail, disables GuardDuty) → dedicated detection-tampering alarm [[60]](60-protect-detection.md) → SNS [[36]](36-sns.md).

---
[< controls index](README.md) | [< home](../README.md)

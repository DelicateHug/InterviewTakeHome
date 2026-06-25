# [27] Lambda redactor (basic reader)

**Type:** Lambda + IAM Function URL

> **In plain terms —** A small function that reads patient records through the access point [26], strips every identifier, and returns only non-sensitive fields. It's the "basic reader" path — the caller never sees raw data.

## Controls applied

- **Prevention:** Reads via the access point [26], strips all identifiers, returns **non-sensitive only**; IAM-auth Function URL is the 'access point' the basic reader calls.
- **Detection:** CloudTrail lambda + invoke events.
- **Alert:** Code / config / policy change → change-alerter [40].

## What would trigger an alert

- The function's code, config, or resource policy is changed (e.g. to stop stripping identifiers) → change-alerter [40] → SNS [36].
- An unauthenticated caller hits the IAM-auth Function URL → AccessDenied → unauthorized-api alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

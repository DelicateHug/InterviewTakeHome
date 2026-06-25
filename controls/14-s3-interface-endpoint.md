# [14] S3 interface endpoint

**Type:** Interface VPC endpoint

> **In plain terms —** A PrivateLink door to S3 that the on-prem node [30] reaches across peering — the gateway endpoint [13] can't be used from there, so this is the only private path in.

## Controls applied

- **Prevention:** PrivateLink S3 reachable across peering by the on-prem node; private DNS disabled; use the `bucket.vpce-...` TLS name for SAN match.
- **Detection:** CloudTrail.
- **Alert:** Endpoint / policy change → change-alerter [40].

## What would trigger an alert

- The endpoint or its policy is changed → change-alerter [40] → SNS [36].
- A read arrives without the matching `aws:sourceVpce` and the bucket denies it → s3-access-denied alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

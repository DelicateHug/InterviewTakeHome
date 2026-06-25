# [25] Vaultless tokenizer

**Type:** Build-time data pipeline

> **In plain terms —** Swaps raw patient identifiers for reversible, epoch-tagged tokens during the data build, so the bucket never stores raw ePHI and there's no token-lookup vault to steal. It also emits a Safe-Harbor de-identified copy for analytics.

## Controls applied

- **Prevention:**
  - AES-SIV deterministic, reversible, epoch-tagged tokens (no vault)
  - rotate-forward
  - produces the tokenized sensitive view plus the Safe-Harbor de-identified view.
- **Detection:** None at runtime — it's an off-cloud build step. The tokens it emits are exactly what the downstream S3 and CloudTrail controls watch.
- **Alert:** None directly. Any attempt to get at the underlying data shows up as a bucket-access alert downstream.

## What would trigger an alert

- Someone tries to read the sensitive bucket [[20]](20-s3-sensitive.md) to recover identifiers from outside the VPC → s3-access-denied alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md).
- The bucket policy protecting the tokenized data is altered → s3-policy-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md).

---
[< controls index](README.md) | [< home](../README.md)

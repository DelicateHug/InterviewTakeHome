# [28] EC2 web app

**Type:** EC2 instance (human read path)

> **In plain terms —** The only way a human reads patient detail: a UI on a private EC2 box reached over SSM (no SSH, no public IP). Even here, identifiers stay tokenized on screen.

## Controls applied

- **Prevention:**
  - The **only** human read path (all 3 admins)
  - SSM-only (no key pair / SSH / public IP)
  - IMDSv2
  - pure-stdlib SigV4 app reads via the gateway endpoint [[13]](13-s3-gateway-endpoint.md)
  - identifiers stay tokenized in the UI.
- **Detection:**
  - CloudTrail
  - SSM session logging.
- **Alert:** Instance / SG change → change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- The instance or its SG [[17]](17-app-sg.md) is modified — e.g. a public IP assigned or SSH opened → change-alerter [[40]](40-change-alerter.md) / sg-change alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md).
- The instance role [[29]](29-ec2-role.md) credentials are stolen and replayed off this instance — from an IP outside AWS, or from another AWS account → GuardDuty `InstanceCredentialExfiltration` [[37]](37-guardduty.md) → SNS [[36]](36-sns.md).

---
[< controls index](README.md) | [< home](../README.md)

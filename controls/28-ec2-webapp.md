# [28] EC2 web app

**Type:** EC2 instance (human read path)

> **In plain terms —** The only way a human reads patient detail: a UI on a private EC2 box reached over SSM (no SSH, no public IP). Even here, identifiers stay tokenized on screen.

## Controls applied

- **Prevention:** The **only** human read path (all 3 admins); SSM-only (no key pair / SSH / public IP); IMDSv2; pure-stdlib SigV4 app reads via the gateway endpoint [13]; identifiers stay tokenized in the UI.
- **Detection:** CloudTrail; SSM session logging.
- **Alert:** Instance / SG change → change-alerter [40].

## What would trigger an alert

- The instance or its SG [17] is modified — e.g. a public IP assigned or SSH opened → change-alerter [40] / sg-change alarm [35] → SNS [36].
- The instance role [29] is assumed from an IP outside the allow-list (stolen creds) → IP-alerter [38].

---
[< controls index](README.md) | [< home](../README.md)

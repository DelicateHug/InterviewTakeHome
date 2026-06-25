# [37] GuardDuty

**Type:** GuardDuty detector

> **In plain terms —** AWS's managed threat detector. It watches for known-bad behaviour (credential misuse, recon, anomalous API calls) with no rules to write, and pages on anything serious.

## Controls applied

- **Prevention:** —. (Detection only — it doesn't block, it reports.)
- **Detection:** Managed threat detection enabled.
- **Alert:** Findings severity >= 4 → EventBridge → SNS [[36]](36-sns.md).

> **Satisfies R12 (role-credential / IP-based alerting) — no custom Lambda.** GuardDuty's
> two managed `InstanceCredentialExfiltration` findings detect EC2 instance-role credentials
> (delivered via IMDS) being used away from the instance they were issued to. This is the
> exact threat a hand-rolled "alert on AssumeRole from an unexpected IP" Lambda was built for,
> but managed, continuously tuned by AWS, and with no allow-list to maintain:
>
> - **`UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS`** — the creds are
>   used from an IP address **outside AWS** (e.g. an attacker replaying stolen keys from their
>   own host). This is the source-IP case.
> - **`UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.InsideAWS`** — the same creds
>   are used from a **different AWS account**. A naive allow-list of AWS IP ranges would miss
>   this; GuardDuty catches it.
>
> Both findings are severity ≥ 4, so they already route through the EventBridge rule → SNS
> [[36]](36-sns.md) below. The on-prem k3s node [[30]](30-onprem-node.md) and the EC2 web app
> [[28]](28-ec2-webapp.md) both receive their roles ([[31]](31-onprem-role.md) / [[29]](29-ec2-role.md))
> as EC2 instance credentials via IMDS, so this coverage applies to both.

## What would trigger an alert

- GuardDuty raises a finding of severity ≥ 4 — e.g. credentials used from a Tor exit node, S3 bucket recon, or anomalous API calls → EventBridge → SNS [[36]](36-sns.md).
- An EC2 instance role is assumed and then used from an unexpected source — an IP outside AWS (`InstanceCredentialExfiltration.OutsideAWS`) or another AWS account (`InstanceCredentialExfiltration.InsideAWS`) → GuardDuty finding → SNS [[36]](36-sns.md). **(R12)**
- An instance or role behaves like compromised credentials (impossible-travel, crypto-mining patterns) → GuardDuty finding → SNS [[36]](36-sns.md).

---
[< controls index](README.md) | [< home](../README.md)

# Detection & Response

> **Summary:** This account watches itself with a multi-region **CloudTrail**, **GuardDuty**, **9 CloudWatch metric-filter alarms**, and a custom **AssumeRole-from-unexpected-IP** Lambda alerter. Everything fans out to one KMS-encrypted **SNS topic** that emails the on-call. This doc catalogs every detection, what each one catches, and what to do when it fires.

Related docs: [Identity & Access](./identity-and-access.md) · [Networking](./networking.md) · [KMS & Encryption](./kms-and-encryption.md) · [S3 & Data Paths](./s3-and-data-paths.md) · Requirement IDs referenced from [REQUIREMENTS.md](../REQUIREMENTS.md) (R7, R12, R15).

Region: **ap-southeast-1**. Workload account: **ith-workload (118821711925)**.

---

## At a glance

| Detection | Type | Triggers on | Sends to |
| --- | --- | --- | --- |
| CloudTrail `ith-trail` | Audit log source | All management + S3 data events | CloudWatch Logs + S3 |
| GuardDuty detector | Threat detection | Findings severity >= 4 | EventBridge -> SNS |
| 9 metric-filter alarms | Log pattern alarms | Specific API patterns in the trail log group | SNS |
| `ith-ip-alerter` (R12) | Custom Lambda | `AssumeRole*` from an IP outside the allowlist | SNS |

All four feed the same alert channel: **SNS topic `ith-security-alerts`** -> email **dylanheathsmart@gmail.com**.

> **You must confirm the SNS email subscription.** AWS sends a confirmation link to that address on first deploy; until someone clicks it, the subscription stays `PendingConfirmation` and **no alerts are delivered**. This is the single most common reason "alarms are configured but I got nothing."

---

## 1. CloudTrail — the source of truth

CloudTrail `ith-trail` is the foundation every alarm reads from.

| Setting | Value |
| --- | --- |
| Scope | **Multi-region** |
| Log file validation | **ON** (tamper-evident digest files) |
| Encryption | **KMS** (`alias/ith/logs`) |
| Destinations | `ith-cloudtrail-118821711925` bucket **and** CloudWatch Logs group `/ith/cloudtrail` |
| Data events | **S3 object-level (data) events on BOTH buckets** (`phi-sensitive-*` and `phi-deident-*`) |
| Status | **`IsLogging = true`** (verified) |

The CloudWatch Logs group `/ith/cloudtrail` is what the 9 metric-filter alarms (Section 3) scan in near-real-time. The S3 bucket is the long-term, validation-protected archive. The trail bucket is named with the account-id suffix per [R7](../REQUIREMENTS.md) and encrypted with the dedicated logs CMK (see [KMS & Encryption](./kms-and-encryption.md)).

Because object-level data events are on, reads/writes against the sensitive bucket are auditable — including every per-patient CMK use behind them (see [R15 per-patient CMK](./kms-and-encryption.md)).

---

## 2. GuardDuty -> SNS

The GuardDuty detector is **enabled** with a **15-minute** finding-publishing cadence.

An EventBridge rule matches GuardDuty findings of **severity >= 4** (high and medium) and forwards them to the **SNS topic**. Low-severity informational findings are intentionally not paged on.

```
GuardDuty finding (severity >= 4) --> EventBridge rule --> SNS topic ith-security-alerts --> email
```

GuardDuty is the "unknown-unknowns" layer: it catches things you didn't write a specific alarm for (crypto-mining, credential exfiltration patterns, anomalous API behavior, known-bad IPs) using AWS-managed threat intelligence.

---

## 3. The 9 CloudWatch metric-filter alarms

Each alarm is a metric filter on the `/ith/cloudtrail` log group. Each fires when its pattern is seen **>= 1 time in a 5-minute window**, and publishes to the **SNS topic**.

| # | Alarm | What it catches | What to do when it fires |
| --- | --- | --- | --- |
| 1 | `root-usage` | Any activity by the account **root** user | Root should almost never be used. Confirm who/why. If unexpected: rotate root credentials, enable/verify root MFA, review what root did in CloudTrail. |
| 2 | `unauthorized-api` | API calls returning **`AccessDenied` / `UnauthorizedOperation`** | Usually benign (mis-scoped role). Identify the principal; if it's reconnaissance (many denies, many services) treat as a probe and review that identity's keys/sessions. |
| 3 | `console-no-mfa` | **Console sign-in without MFA** | All human access should be MFA-enforced via Identity Center + the Conditional Access phishing-resistant-MFA grant (see [Identity & Access](./identity-and-access.md)). A no-MFA console login means a local IAM user slipped the guardrail — find and remediate it. |
| 4 | `iam-policy-change` | Create/update/delete of IAM **policies, roles, users, attachments** | Confirm it's an intended change (Terraform run / approved admin). Unexpected IAM changes are a top privilege-escalation signal — diff the change and revert if unauthorized. |
| 5 | `s3-policy-change` | Changes to **S3 bucket policy / ACL / public-access** settings | Verify it wasn't an attempt to open a PHI bucket. Confirm Block Public Access is still ON and the bucket policy still enforces org-only + VPC-endpoint gates (see [S3 & Data Paths](./s3-and-data-paths.md)). |
| 6 | `kms-disable-delete` | **Disabling or scheduling deletion** of a KMS key | High impact: disabling a per-patient CMK makes exactly that patient's data unreadable (that is by design, but it should never be accidental). Confirm intent; if malicious, cancel the deletion immediately (within the 7-day window). |
| 7 | `cloudtrail-change` | **Stopping / deleting / reconfiguring CloudTrail** | This is a classic "turn off the cameras" move. Treat as high severity: re-enable logging, verify `IsLogging=true`, and investigate the principal that touched the trail. |
| 8 | `sg-change` | **Security group** ingress/egress changes | Confirm the change matches an approved deployment. Watch for newly opened inbound rules — the design is SSM-only with no public ingress (see [Networking](./networking.md)). |
| 9 | `s3-access-denied` | **S3 requests denied** (e.g. blocked by the VPC-endpoint / org / TLS guardrails) | Often expected: a laptop with no VPC endpoint trying to read the sensitive bucket is *supposed* to be denied. Use it to confirm the controls are working; investigate only if a *legitimate* path is being denied or if denies spike from one principal. |

> **Why "5-minute, >= 1" is fine here:** these are security signals, not noisy ops metrics. One occurrence is worth a look. Tune the period only if a specific alarm proves chatty.

---

## 4. R12 — AssumeRole-from-unexpected-IP alerter

This is a custom detection for **[R12](../REQUIREMENTS.md)**: alert when someone assumes a role from an IP you didn't expect.

### How it works

```
sts:AssumeRole / AssumeRoleWithSAML / AssumeRoleWithWebIdentity
        |
        v
EventBridge rule  ith-assume-role-ip
        |
        v
Lambda  ith-ip-alerter
        |  (is sourceIPAddress a real external IP NOT in allowed_assume_role_cidrs?)
        v
SNS topic ith-security-alerts  --> email
```

1. An **EventBridge rule** (`ith-assume-role-ip`) matches the three STS `AssumeRole*` event names from CloudTrail.
2. It invokes the **Lambda `ith-ip-alerter`**.
3. The Lambda reads `sourceIPAddress` from the event and checks it against the allowlist variable **`var.allowed_assume_role_cidrs`**.
4. If the IP is a **real external IP that is NOT in the allowlist**, the Lambda publishes an alert to **SNS**.
5. **AWS-service callers are ignored** — internal service principals (e.g. `*.amazonaws.com` source identifiers, AWS-internal IPs) don't fire the alert, so you only see human/external assumptions.

### The empty-allowlist demo behavior

`var.allowed_assume_role_cidrs` **defaults to EMPTY**. With an empty allowlist, *every* external-IP role assumption is "not in the allowlist," so the alerter **demonstrably fires** — this is intentional, so the detection is visibly working out of the box.

> **In production:** set `allowed_assume_role_cidrs` to your **admin egress CIDRs** (the office / VPN / break-glass ranges). Then the alerter only fires on assumptions from *unexpected* locations, which is the real signal.

### What to do when it fires

1. Note the **role** assumed, the **principal**, and the **source IP** from the alert.
2. Is the IP a known admin egress that simply isn't in the allowlist yet? -> add it to `allowed_assume_role_cidrs`.
3. Is it genuinely unexpected? -> treat as a potential credential compromise: review that identity's recent CloudTrail activity, revoke active sessions, rotate credentials, and check whether the assumed role touched PHI buckets or KMS.

---

## 5. The alert channel — SNS topic `ith-security-alerts`

| Setting | Value |
| --- | --- |
| Topic | `ith-security-alerts` |
| Encryption | **KMS** (`alias/ith/logs`) |
| Subscription | **email -> dylanheathsmart@gmail.com** |
| Status | **must be confirmed** (click the link AWS emails) |

Everything in this doc converges here: GuardDuty findings, all 9 metric-filter alarms, and the R12 IP alerter. One channel, one inbox, KMS-encrypted at rest.

**If you are not receiving alerts, check this first:** the subscription must be **Confirmed**, not `PendingConfirmation`.

---

## 6. General response runbook

When any alert lands, work the same loop:

1. **Triage** — open CloudTrail (or the GuardDuty finding) and identify the *principal*, *source IP*, *action*, and *result*.
2. **Decide expected vs. not** — was this a Terraform apply, an approved admin, or a known service? Many alarms (`s3-access-denied`, `unauthorized-api`) are often the controls working as designed.
3. **Contain** — if not expected: revoke sessions, rotate/disable credentials, and for KMS/CloudTrail tampering reverse the action immediately (KMS deletion has a 7-day cancel window; re-enable CloudTrail).
4. **Investigate scope** — pivot in CloudTrail from the principal to everything else it did, especially PHI bucket reads and KMS use (object-level data events make this possible).
5. **Close the loop** — if the alert was a tuning gap (e.g. a legit admin IP not in `allowed_assume_role_cidrs`), update config so the next one is signal.

---

## 7. Known scope notes

These were **considered, not missed** (see [REQUIREMENTS.md](../REQUIREMENTS.md) out-of-scope list):

- **Dedicated root-usage alerting** typically lives in a management/org-level account. Here we alarm on root usage with what's available **inside the workload account** (`root-usage` filter).
- **Centralized logging** (a dedicated Log Archive account) and **Amazon Inspector** are out of scope for this take-home; CloudTrail logs land in-account with log-file validation and a KMS-encrypted bucket as the next-best control.

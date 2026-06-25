# Design — Prevent / Detect / Respond + Failure Modes

> **Summary:** This system protects a bucket of ePHI using **defense-in-depth** and an
> **assume-breach** mindset, organized as three jobs — **PREVENT** unauthorized access,
> **DETECT** it fast when prevention slips, and **RESPOND** to contain it. Every control
> below is **deployed** (Terraform, account `118821711925`, region `ap-southeast-1`) and
> tied to a real resource. The guiding rule for the data is **fail-closed on
> confidentiality**: when a dependency breaks, the safe outcome is *no access to PHI*,
> not degraded-but-open access.

Related docs:
[`README.md`](../README.md) ·
[`REQUIREMENTS.md`](../REQUIREMENTS.md) ·
[`data-plane-paths.md`](data-plane-paths.md) ·
[`identity-and-mfa.md`](identity-and-mfa.md) ·
[`encryption-and-tokenization.md`](encryption-and-tokenization.md) ·
[`detection-and-response.md`](detection-and-response.md) ·
[`tradeoffs-and-out-of-scope.md`](tradeoffs-and-out-of-scope.md)

---

## 1. The threat model in one paragraph

The asset is a single S3 bucket of synthetic patient records,
`phi-sensitive-118821711925` ([R1](../REQUIREMENTS.md)). We assume the perimeter
**will** be breached: a credential leaks, a laptop is stolen, a node is popped, an admin
goes rogue, or a region falls over. So no single control is trusted to hold. We layer
**organization guardrails → identity → network → encryption → tokenization**, then watch
all of it and wire alerts to a human. If a layer fails, the layers beneath it still deny,
and the breach gets *louder*, not quieter.

---

## 2. Defense-in-depth: the layers

Read this top-to-bottom as concentric rings around the data. An attacker has to defeat
**every** ring, and each ring is a separate AWS construct enforced by a different control
plane.

| # | Layer | What it stops | As-built resource |
|---|---|---|---|
| 1 | **Org guardrails (SCP + RCP)** | Account-level mistakes & out-of-org principals | SCP `ith-scp-s3-guardrails` + RCP `ith-rcp-s3-org-only` on OU `ou-33e3-5p8xygxw` |
| 2 | **Identity (who)** | Wrong human / weak auth / over-broad rights | Identity Center perm-sets `ITH-SuperAdmin` / `ITH-Admin` / `ITH-S3Reader`; Entra CA (phishing-resistant MFA, doc-only) |
| 3 | **Network (from where)** | Access from anywhere but the private VPC path | Fully-private workload VPC `10.20.0.0/16`, S3 gateway/interface endpoints, `aws:sourceVpce` bucket gate |
| 4 | **Resource policy (to what)** | Direct GETs, insecure transport, public access | Sensitive-bucket policy, Block Public Access, TLS-only deny |
| 5 | **Encryption at rest (KMS)** | Reading bytes without the key | Per-patient CMKs `alias/ith/patient/<hex>`, plus `alias/ith/deident`, `alias/ith/logs` |
| 6 | **Tokenization (what's in the bytes)** | PHI exposure even if all the above fail | Vaultless AES-256-SIV field tokens; de-identified second bucket |

The key property: rings 1–4 are *access* controls; rings 5–6 are *data* controls. Even a
principal who somehow wins the access fight still pulls **tokenized** objects encrypted
under a **per-subject** key. That is assume-breach made literal.

---

## 3. PREVENT

Stop unauthorized access before it happens.

### 3.1 Organization guardrails (R8, R9)

The SCP and RCP attach to the `InterviewTakeHome` OU **only** — nothing on the user's
existing accounts.

- **SCP `ith-scp-s3-guardrails`** (`p-kt4wutiz`) denies, for everyone in the OU:
  S3 over insecure transport; `PutObject` to `phi-*` unless the SSE header is
  `aws:kms`; `PutObject` to `phi-*` with the header absent; and disabling
  account-level Block Public Access (except `OrganizationAccountAccessRole`). This is a
  *ceiling* no IAM policy in the account can exceed.
- **RCP `ith-rcp-s3-org-only`** (`p-02p8l548gj`) denies `s3:*` whenever
  `aws:PrincipalOrgID != o-ncxqr8pp2c` (and the caller is not an AWS service). This
  blocks any principal **outside the org** — the confused-deputy / cross-account
  exfiltration case — on the resource side, regardless of bucket policy.

Both policy types are **ENABLED** on org root `r-33e3`.

### 3.2 Identity — least privilege + strong auth (R2, R3, R10, R13)

Three permission sets are **created for real** (inert until assigned):

| Permission set | Grant | Notable deny |
|---|---|---|
| `ITH-SuperAdmin` | `AdministratorAccess` | — (break-glass) |
| `ITH-Admin` | s3/ec2/cloudwatch/logs/cloudtrail/guardduty/sns/ssm + `iam:Get*/List*` | **explicit `Deny kms:*`** — admins manage infra but can **never** touch the keys |
| `ITH-S3Reader` | `s3:GetObject`/`ListBucket` on the phi buckets **only when `aws:sourceVpce = vpce-0d4239508db2903d7`**, plus `kms:Decrypt` | denied everywhere else by the absent condition |

The `ITH-Admin` KMS deny is the **separation-of-duties** hinge: the people who run the
platform are not the people who can decrypt patient data.

Authentication strength is the IdP's job. The Entra **Conditional Access** policy requires
authentication strength = built-in **"Phishing-resistant MFA"**
(`…/authenticationStrengthPolicies/00000000-0000-0000-0000-000000000004`) for the
`ITH-Interview-Admins` group on the AWS app. Because that is the **only** accepted grant,
plain password / SMS / non-phishing-resistant MFA is **blocked** outright. Entra **P1**
licensing is present so CA is enforceable.

> These Entra objects (users, group, CA policy, account assignments) are **written as
> Terraform but disabled** (`var.enable_entra_changes = false`) to honor the
> no-breaking-changes guardrail on the live `delicatehug.com` tenant. They are
> documented-as-suggested. The **AWS** perm-sets are real. See
> [`identity-and-mfa.md`](identity-and-mfa.md).

### 3.3 Network — private-only, VPC-gated (R16, R17)

The workload VPC `10.20.0.0/16` has **no IGW and no NAT** — there is no route to the
internet at all. S3 is reached only through VPC endpoints:

- an **S3 gateway endpoint** (`vpce-0d4239508db2903d7`) for in-VPC clients, and
- an **S3 interface endpoint** (`vpce-000ca0be99fa5595c`) so the peered on-prem VPC can
  reach S3 over the peering (gateway endpoints are **not** reachable across peering — the
  concrete reason the on-prem path needs the interface endpoint).

Security groups use **SG-as-source**, not CIDRs (R17): the endpoints SG admits 443 *from
the app SG* and *from the on-prem node SG* (a cross-VPC SG reference over the peering);
the app SG has **no inbound at all** (SSM only). This means "who may talk to S3's
endpoint" is expressed as *identity of the workload*, not a brittle IP range.

### 3.4 Resource policy — the bucket says no by default (R1, C1)

`phi-sensitive-118821711925` is SSE-KMS (per-patient CMK on each object), versioned, with
**Block Public Access ON**. Its bucket policy denies: insecure transport; out-of-org
principals; and `GetObject`/`GetObjectVersion`/`ListBucket` **unless** the request comes
through `vpce-0d4239508db2903d7` / `vpce-000ca0be99fa5595c` **or** a same-account access
point — excluding AWS services.

**Verified effect:** a human laptop with no VPC endpoint is **DENIED**. Humans therefore
*cannot* read PHI directly — they must go through the EC2 web app (C1). The four
deliberate read paths are documented in [`data-plane-paths.md`](data-plane-paths.md);
P4 (the `s3` principal) is the live proof — same call **fails** from a laptop and
**succeeds** from inside the VPC.

### 3.5 Encryption & tokenization — data controls (R15, R18, C4)

- **Per-patient KMS CMK** (R15): one customer-managed key per patient (7 keys), rotation
  on, key policy = account root + the 4 reader roles for `Decrypt`/`GenerateDataKey*`/
  `DescribeKey`. Blast-radius is **per subject**: disable one key and exactly one
  patient goes dark. (Cost/sprawl tradeoff and the recommended prod alternative — one
  CMK + per-patient data keys / encryption context — are in
  [`tradeoffs-and-out-of-scope.md`](tradeoffs-and-out-of-scope.md).)
- **Vaultless tokenization** (R18): sensitive fields are replaced *before upload* by
  deterministic, reversible, epoch-tagged tokens
  (`tok:v{epoch}:{base64url(AES-SIV(value, AAD=fieldname))}`). There is no token vault to
  breach — the token is derived cryptographically. SSE-KMS then encrypts the whole object
  on top (defense in depth). The second bucket `phi-deident-118821711925` (C4) is a
  Safe-Harbor-style de-identified copy (HMAC pseudo-id, age band not DOB, state not
  address) that is readable anywhere **in the org** but still org-locked and TLS-only.
  See [`encryption-and-tokenization.md`](encryption-and-tokenization.md).

---

## 4. DETECT

Assume prevention eventually fails — make sure the failure is visible within minutes.

- **CloudTrail `ith-trail`** — multi-region, **log-file validation ON**, KMS-encrypted
  (`alias/ith/logs`), delivering to `ith-cloudtrail-118821711925` **and** CloudWatch Logs
  group `/ith/cloudtrail`, with **S3 object-level (data) events on both buckets**.
  `IsLogging=true` verified. Object-level events mean every individual GET on a patient
  record is recorded.
- **GuardDuty** — detector enabled (15-min findings). Findings of severity ≥ 4 flow
  **GuardDuty → EventBridge → SNS**.
- **9 CloudWatch metric-filter alarms** on the trail log group, each firing at ≥ 1 event
  in 5 minutes → SNS: root-usage, unauthorized-api, console-no-mfa, iam-policy-change,
  s3-policy-change, kms-disable-delete, cloudtrail-change, sg-change, s3-access-denied.
- **Role-assumption IP alerting** (R12) — EventBridge rule `ith-assume-role-ip` on
  `AssumeRole` / `AssumeRoleWithSAML` / `…WithWebIdentity` → Lambda `ith-ip-alerter` →
  SNS when the source IP is a real external address not in
  `var.allowed_assume_role_cidrs` (default **empty** so it demonstrably fires; set to
  admin egress CIDRs in prod). AWS-service callers are ignored.

The full catalog is in [`detection-and-response.md`](detection-and-response.md).

---

## 5. RESPOND

Every detection lands somewhere a human acts on it, and several controls double as
containment levers.

- **Single alert sink** — SNS topic `ith-security-alerts` (KMS-encrypted), email
  subscription to `dylanheathsmart@gmail.com` (subscription must be confirmed). All
  alarms, GuardDuty findings, and the IP-alerter Lambda publish here.
- **Per-patient containment** — because each patient has its own CMK, the first-line
  response to a suspected single-subject compromise is **disable that one key**: that
  patient's objects become unreadable instantly with no effect on the other six, and the
  action itself is audited.
- **Tamper-evidence** — CloudTrail log-file validation plus the `cloudtrail-change` and
  `kms-disable-delete` alarms mean an attacker trying to *cover tracks* (stop the trail,
  schedule key deletion) trips an alert in the act.
- **Revoke / re-scope** — perm-sets are the unit of revocation; the `ITH-Admin` `Deny
  kms:*` ensures an attacker who lands an admin session still cannot decrypt while you
  respond.

---

## 6. Controls summary matrix (layer × Prevent / Detect / Respond)

| Layer | PREVENT | DETECT | RESPOND |
|---|---|---|---|
| **Org guardrails** | SCP TLS/KMS/BPA denies; RCP out-of-org deny (R8/R9) | `s3-policy-change`, `s3-access-denied` alarms | RCP/SCP block the blast radius org-wide; tighten OU policy |
| **Identity** | Least-priv perm-sets; `ITH-Admin` `Deny kms:*`; phishing-resistant MFA CA (R2/R3/R13) | `console-no-mfa`, `unauthorized-api`, `iam-policy-change`, AssumeRole-IP (R12) | Revoke/re-scope perm-set; KMS deny holds during response |
| **Network** | Private VPC (no IGW/NAT); `aws:sourceVpce` gate; SG-as-source (R16/R17) | `sg-change` alarm; CloudTrail VPC-endpoint context | Pull SG rule / endpoint policy to sever a path |
| **Resource policy** | Bucket deny: insecure transport, out-of-org, non-VPCE GET; BPA on (R1/C1) | object-level data events on both buckets | Patch bucket policy; deny the offending principal |
| **Encryption (KMS)** | Per-patient CMK; `ITH-Admin` cannot use keys (R15) | `kms-disable-delete` alarm; per-key CloudTrail | **Disable one patient's CMK** → that subject goes dark |
| **Tokenization** | Fields tokenized pre-upload; de-id copy drops identifiers (R18/C4) | (data-control, not event-emitting) | Rotate-forward to a new epoch; retire old DEK |
| **Logging/visibility** | CloudTrail multi-region + validation; GuardDuty (R11) | 9 alarms + GuardDuty → EventBridge → SNS (R4) | All paths → SNS email; `cloudtrail-change` flags tamper |

---

## 7. Failure-mode walkthrough (assume-breach)

For each failure, the question is the same: **what still protects the PHI?** The governing
principle is **fail-closed on confidentiality** — if a control's dependency is down, the
correct behavior is to *deny access*, never to fall open.

### 7.1 Auth / IdP (Entra) is down
Federated sign-in to the AWS portal stops, so **no new admin sessions** can be
established — the human read path (P3, EC2 web app, reached only via authenticated SSM)
is unavailable. This is **fail-closed**: an outage at the IdP removes access rather than
bypassing MFA. Automated paths that use IAM roles (P1 Lambda, P2 on-prem node) are
unaffected by IdP state, and they only ever return **redacted** (P1) or already-tokenized
(P2) data. Break-glass remains the `ITH-SuperAdmin` perm-set, itself behind the same CA
when enabled.

### 7.2 KMS is down (or a key is disabled)
Objects are SSE-KMS, so if KMS is unavailable, **`GetObject` fails** — the bytes cannot be
decrypted. PHI is therefore **inaccessible, not exposed** (fail-closed). If a *single*
patient key is disabled (deliberately, as a response action, or by fault), exactly **one**
patient goes dark and the other six are fine — the per-patient-CMK blast-radius property
(R15). A `kms-disable-delete` alarm fires if a key is disabled or scheduled for deletion,
so an *attacker*-driven key change is also loud.

### 7.3 A node is compromised (EC2 web app or on-prem k3s)
The hosts are hardened to shrink what a foothold yields:

- **No SSH, no key pair, no public IP**; access is **SSM-only** (C3). The app SG has
  **no inbound**. So lateral movement *into* the host over the network is already denied.
- A compromised host can still use its **instance role** to read S3 — but the EC2 web app
  renders records with identifiers **still tokenized** (even the human path never shows
  raw PHI, verified), and the on-prem `aws-cli` CronJob likewise pulls tokenized objects.
  The attacker gets ciphertext-of-meaning, not names and SSNs.
- The node's reads are **VPC-endpoint-gated and object-level logged**; an anomalous read
  burst surfaces via `s3-access-denied` / object-data events, and a stolen role assumed
  from an external IP trips the **R12 IP-alerter**.
- IMDS `hop_limit = 2` is deliberately scoped so pods can reach IMDS; the node is
  otherwise least-privilege via `ith-onprem-k8s-role` / `ith-ec2-webapp-role`.

### 7.4 Insider / over-privileged admin
Separation of duties is the answer. `ITH-Admin` can run the platform but carries an
**explicit `Deny kms:*`** — an admin (or an attacker who steals an admin session)
**cannot decrypt patient data** no matter how the IAM policies are bent, because an
explicit deny wins. Any IAM/policy edits they attempt fire `iam-policy-change` /
`s3-policy-change` / `console-no-mfa`, and root usage fires `root-usage`. The only
all-powerful set is `ITH-SuperAdmin` (break-glass), gated by phishing-resistant MFA when
Entra changes are enabled.

### 7.5 Logging pipeline fails
Two cases. If CloudTrail is **tampered with** (stopped, reconfigured), the
`cloudtrail-change` metric-filter alarm fires and **log-file validation** makes after-the-
fact gaps/edits detectable. If the **alerting sink** degrades (SNS/email), the events are
still durably retained in the `ith-cloudtrail-118821711925` bucket *and* the
`/ith/cloudtrail` CloudWatch Logs group for later forensics — detection is delayed, not
lost. The logging bucket and topic are themselves KMS-encrypted (`alias/ith/logs`).
*Confidentiality of PHI is independent of the logging plane* — a broken pipeline never
opens the data.

### 7.6 Region outage (ap-southeast-1)
This is the honest gap. The workload is **single-region**, so a regional outage means the
PHI is **unavailable** until the region recovers — again **fail-closed on
confidentiality** (unavailable, never exposed). Cross-region resilience (AWS Backup with
immutable cross-region copies, Application Recovery Controller for failover routing) is
**explicitly out of scope** for this access-control demo and is called out as *considered,
not missed* in [`tradeoffs-and-out-of-scope.md`](tradeoffs-and-out-of-scope.md). Note
CloudTrail itself **is** multi-region, so the audit trail is more resilient than the data
plane.

### Failure-mode summary

| Failure | Confidentiality outcome | What still protects PHI | Detection |
|---|---|---|---|
| IdP / auth down | Fail-closed (no new sessions) | Human path needs auth'd SSM; automation returns redacted/tokenized | sign-in failures at IdP |
| KMS down / key disabled | Fail-closed (GET fails) | Whole object is SSE-KMS; one key = one patient | `kms-disable-delete` |
| Node compromised | Data stays tokenized | SSM-only, no SSH/inbound; tokenized output; least-priv role | object-events, R12 IP-alerter |
| Insider / over-priv admin | Cannot decrypt | `ITH-Admin` explicit `Deny kms:*`; SoD | `iam-policy-change`, `root-usage` |
| Logging pipeline fails | Unaffected (independent) | PHI controls don't depend on logs; durable retention | `cloudtrail-change`, log-file validation |
| Region outage | Fail-closed (unavailable) | Out-of-scope HA; data never exposed | multi-region CloudTrail intact |

---

## 8. Fail-closed-on-confidentiality — the stance, stated plainly

Across every failure above the same decision repeats: when a dependency is unavailable,
the system **denies access to PHI** rather than degrading into an open state. Encryption
that can't reach KMS returns errors, not plaintext. An IdP outage removes sessions, it
doesn't waive MFA. A region outage makes data unavailable, it doesn't replicate it
somewhere unguarded. We accept **availability** risk to guarantee **confidentiality** —
the right trade for ePHI.

---

## 9. Known limits & successors (documented, not hidden)

- **VPC peering doesn't scale** — it is non-transitive and N² (each new VPC needing the
  data tier adds a peering + routes on both sides). **Transit Gateway** (or PrivateLink to
  one endpoint service) is the scalable successor; peering was chosen deliberately to
  match the brief and make the tradeoff concrete.
- **S3 Object Lambda pivot** — P1 was intended as an S3 **Object Lambda** Access Point,
  but AWS gates Object Lambda creation to existing customers (a brand-new account gets
  `AccessDenied`), so we shipped the supported equivalent: **Lambda + standard Access
  Point + IAM-auth Function URL**. Same outcome (redacted fields only). Details in
  [`data-plane-paths.md`](data-plane-paths.md).
- **Per-patient CMK cost/sprawl** and the recommended one-CMK-plus-data-keys alternative,
  the **VPC-endpoint operational overhead**, and the full **out-of-scope** list (Control
  Tower, AWS Backup, ALB, ARC, centralized Log Archive account, Amazon Inspector) are in
  [`tradeoffs-and-out-of-scope.md`](tradeoffs-and-out-of-scope.md).

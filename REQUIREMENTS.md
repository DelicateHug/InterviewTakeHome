# Requirements Traceability Matrix

> Single source of truth for this take-home. Every requirement the interviewer gave
> (and every clarification since) is listed here with: the literal ask, how this build
> interprets it, **how it is satisfied**, and status. Read top-to-bottom to grade.

**Scenario:** Secure a sensitive resource (an **S3 bucket of ePHI / health data**) in
the cloud - preventing, detecting, and responding to unauthorized access, and holding
up when something fails. Everything is **Infrastructure-as-Code (Terraform)** and
**actually deployed** to an isolated account, then torn down after verdict.

> **STATUS: DEPLOYED & VERIFIED** - all requirements are live in account `118821711925`
> and verified with real calls; see [`docs/EVIDENCE.md`](docs/EVIDENCE.md). The only
> items not applied are the **Entra Conditional Access + users** (R2/R3/R10 and the user
> side of R13): written as Terraform but **left disabled** to honor the owner's
> no-breaking-changes guardrail on the live tenant.

Status legend: **DONE** = deployed & verified - **DOC-ONLY** = IaC written but
intentionally not applied (guardrail) - **PARTIAL** = partly real, partly doc-only.

---

## 0. Live environment facts (discovered, not assumed)

| Thing | Value |
|---|---|
| AWS Organization | `o-ncxqr8pp2c` (FeatureSet ALL), root `r-33e3` (SCP + RCP both enabled) |
| Management account | `337066574719` (dylanheathsmart@gmail.com) |
| New isolated OU | `InterviewTakeHome` = `ou-33e3-5p8xygxw` |
| New member account | `ith-workload` = **`118821711925`** (dylanheathsmart+ith-workload@gmail.com) |
| SCP / RCP | `p-kt4wutiz` (S3 guardrails) / `p-02p8l548gj` (deny S3 outside org) - on the OU only |
| Identity Center | instance `ssoins-46812a8af28769cf`, store `d-96677e53fe`; Entra-fed via SCIM |
| AWS access portal (login URL) | **https://d-96677e53fe.awsapps.com/start/** |
| Entra tenant | `delicatehug.com` (`16a0c46e-...`), AAD_PREMIUM (P1) present |
| Region | `ap-southeast-1` |

> **Isolation discipline:** SCP/RCP attach **only** to the new OU; nothing touches the
> existing accounts (DSOAR-*, Cyber Champion) or the owner's identity.
>
> ### Non-breaking guardrail (owner instruction)
> - **AWS** - only additive, isolated resources are deployed: the new OU, the new member
>   account, workload resources in it, and SCP/RCP on the new OU only. CloudTrail/GuardDuty
>   are account-level (not org-wide), so existing accounts are untouched.
> - **Entra** - Conditional Access (phishing-resistant MFA, non-MFA block) and the 3 Entra
>   users are written as IaC but **NOT applied** (`var.enable_entra_changes=false`), so the
>   live tenant and its 7 existing CA policies are not changed. The AWS Identity Center
>   **permission sets ARE created for real** (inert until assigned); the user assignments are
>   doc-only because they depend on the not-provisioned Entra users.

---

## 1. Hard requirements

| # | Requirement (as given) | How satisfied | Status |
|---|---|---|---|
| R1 | **S3 bucket with sensitive data** | `phi-sensitive-118821711925` holds tokenized ePHI; SSE-KMS, BPA on, TLS-only, VPC-locked. | DONE |
| R2 | **Phishing-resistant MFA** via the IdP | Entra CA requires auth strength = Phishing-resistant MFA (`...0004`) for the admin group on the AWS app. | DOC-ONLY |
| R3 | **Non-MFA blocked** | Same CA policy: the only accepted grant is the phishing-resistant strength, so password-only / non-MFA is blocked. | DOC-ONLY |
| R4 | **Alerting** ("alarms for everything") | SNS `ith-security-alerts` + 9 CloudWatch metric-filter alarms + GuardDuty->SNS + the R12 IP alerter. 3 alarms already firing on real activity. | DONE |
| R5 | **Everything is IaC** | 100% Terraform: `00-org`, `10-identity`, `20-workload`. | DONE |
| R6 | **1 mgmt acct + 1 OU + 1 account in the OU** | Mgmt `337066574719` -> OU `InterviewTakeHome` -> member `ith-workload` (created via `aws_organizations_account`). | DONE |
| R7 | **S3 inter-account suffix naming** | `phi-sensitive-<acct>`, `phi-deident-<acct>` - account id suffix = globally unique + traceable. | DONE |
| R8 | **S3 must require an org-level SCP** | SCP `p-kt4wutiz` on the OU: deny non-TLS S3, deny PHI PutObject without SSE-KMS, protect account BPA. | DONE |
| R9 | **RCP must stop S3 to outer org** | RCP `p-02p8l548gj` on the OU: deny `s3:*` when `aws:PrincipalOrgID != o-ncxqr8pp2c` (excl. AWS services). | DONE |
| R10 | **IdP requires phishing-resistant MFA** | = R2 (Entra is the IdP; federation reused). | DOC-ONLY |
| R11 | **CloudTrail + GuardDuty enabled** | `ith-trail` (multi-region, log-file validation, KMS, S3 data events, -> CW Logs). GuardDuty detector ENABLED. | DONE |
| R12 | **Role assumptions -> IP-based alerting** | EventBridge on `AssumeRole*` -> Lambda `ith-ip-alerter` -> SNS when source IP outside the allow-list. Verified firing. | DONE |
| R13 | **3 users** + README login URL | `ITH-SuperAdmin` (all), `ITH-Admin` (scoped, **deny kms:***), `ITH-S3Reader` (read S3 **only in-VPC**). Permission sets real; Entra users doc-only. Login URL on README p.1. | PARTIAL (perm-sets real / users doc-only) |
| R14 | **Synthea, >=5 patient records** | 7 synthetic patients (FHIR -> tokenized). | DONE |
| R15 | **S3 KMS, "per person"** -> per-patient CMK | One customer-managed KMS key **per patient** (7), object encrypted under its patient's CMK. Cost-vs-compliance documented (s.4). | DONE |
| R16 | **4 paths to the bucket** | Lambda redactor (P1), on-prem k8s over peering (P2), EC2 web app SSM-only (P3), `s3` user gated on `aws:sourceVpce` (P4). All verified. | DONE |
| R17 | **Security group as allow + port** | SG-as-source rules: endpoints SG <= app SG:443 and <= on-prem node SG:443 (cross-VPC over peering). No CIDR allows on the data plane. | DONE |
| R18 | **Vaultless tokenization** | Deterministic, reversible, epoch-tagged AES-SIV tokens (no vault); rotate-forward. Round-trip verified. | DONE |
| R19 | **Diagrams + readable docs** | Editable draw.io (4 pages) with `[NN]` IDs -> controls index, + 7 docs. | DONE |

## 1a. Clarifications added mid-flight

| # | Added requirement | How satisfied | Status |
|---|---|---|---|
| C1 | **All 3 admins read details only via the EC2 web UI** | No human identity has direct `GetObject` on the sensitive bucket (verified AccessDenied from laptop); humans use the EC2 app, which reads via the instance role from inside the VPC. | DONE |
| C2 | **Lambda "basic reader" transforms to non-sensitive** | Lambda `ith-redactor` (Function URL) reads via an S3 Access Point and returns only de-identified fields. Verified. | DONE |
| C3 | **No EC2 login - use SSM** | EC2 has no key pair / no SSH / no public IP; access via SSM Session Manager only. | DONE |
| C4 | **2nd bucket viewable outside the VPC** | `phi-deident-118821711925` holds the de-identified copy, readable anywhere in the org (still org-locked, TLS, KMS). | DONE |

---

## 2. The four access paths to the (sensitive) bucket

| Path | Caller | Route | Authz | Returns |
|---|---|---|---|---|
| **P1 Lambda redactor** | basic reader | invoke `ith-redactor` Function URL -> S3 Access Point | IAM + access-point delegation | **non-sensitive** fields only |
| **P2 On-prem k8s** | k3s pod | **VPC peering** -> S3 **interface** endpoint | node role + `aws:sourceVpce` | full object |
| **P3 EC2 web app** | human admins (all 3) | SSM port-forward -> EC2 app -> S3 **gateway** endpoint | EC2 instance role (humans have no direct S3) | rendered record (identifiers tokenized) |
| **P4 `s3` user** | the `s3` identity | CLI/SDK **from inside the VPC** only | IAM + bucket policy `aws:sourceVpce` | full object, VPC-gated |

> **Peering scalability caveat:** peering is non-transitive & N^2; Transit Gateway is the
> scalable successor. Used here deliberately to match the brief.
> **Gateway vs interface:** gateway endpoints aren't reachable across peering, which is
> exactly why P2 (on-prem) needs the S3 *interface* endpoint.

---

## 3. Out of scope (considered, intentionally excluded)

- **AWS Control Tower** - automates landing zone/guardrails; overkill for 1-OU/1-account.
- **AWS Backup / recovery** - immutable cross-region tested restores; orthogonal to access control.
- **ALB** - no public web tier; EC2 reached via SSM.
- **Application Recovery Controller** - multi-region failover; no HA region here.
- **Root-account usage alerting** - root lives in the mgmt account we don't fully own.
- **Centralized logging** (dedicated Log Archive account) - kept logs in the workload account.
- **Amazon Inspector** - runtime/SCA vuln scanning; orthogonal to the access-control story.

**VPC-endpoint note:** requiring all S3 access via VPC endpoints is overhead (extra
resources, endpoint policies, the silent public-endpoint fallback trap) but for sensitive
data it is a strong control - it keeps traffic on the AWS backbone and powers the
`aws:sourceVpce` gate behind P3/P4.

---

## 4. Documented tradeoffs (full detail in [`controls/OutOfScopeNotes.md`](controls/OutOfScopeNotes.md))

- **Per-patient KMS CMK - cost vs compliance.** Upside: per-subject crypto blast radius
  (disable one key -> one patient dark) + per-key audit. Downside: ~$1/key/month, ~100k
  keys/region soft limit, key sprawl. Recommended prod alternative: one CMK + per-patient
  data keys / encryption context (same audit + isolation, no sprawl). We implemented the
  literal per-patient-CMK as asked.
- **Vaultless tokenization.** No vault to run/secure/scale; tokens carry the key epoch;
  rotate forward without mass re-tokenization. Tradeoff: deterministic tokens enable joins
  (a re-identification surface) - acceptable for de-identified analytics.
- **VPC peering** - N^2 / non-transitive; TGW is the successor (see s.2).

---

## 5. Deliverables

- [x] `terraform/00-org` - OU, member account, SCP, RCP (applied)
- [x] `terraform/10-identity` - permission sets (applied); Entra/CA (doc-only)
- [x] `terraform/20-workload` - KMS, 2x S3, VPCx2 + peering + endpoints, SGs, EC2, Lambda, detection (applied)
- [x] `app/` - web app, redactor Lambda, IP-alerter, vaultless tokenizer
- [x] `data/` - 7 Synthea patients, tokenized
- [x] `diagrams/` - draw.io (4 pages) + `[NN]` controls index
- [x] `docs/` - design, paths, identity, crypto, detection, tradeoffs, EVIDENCE
- [x] `README.md` - page 1: 3 users + login URL
- [x] `scripts/` - data upload + teardown runbook

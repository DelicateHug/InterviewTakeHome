# Securing a Sensitive S3 Resource — AWS + Entra (Take-Home)

A fully Infrastructure-as-Code (Terraform) design for protecting an **S3 bucket of
sensitive health data (ePHI)** — built around **Prevent → Detect → Respond** and the
**assume-breach** principle. Synthetic patient data is generated with **Synthea**,
**vaultless-tokenized**, and encrypted with **per-patient KMS keys**.

> **Grading shortcut:** [`REQUIREMENTS.md`](REQUIREMENTS.md) is a line-by-line
> traceability matrix — every requirement → how it's satisfied → status.

---

## 1. The three users and where to log in

**AWS access portal (login URL):** **https://d-96677e53fe.awsapps.com/start/**

Identity is **Microsoft Entra ID** (the IdP), federated into **AWS IAM Identity
Center** (SCIM-provisioned). Sign-in is gated by **phishing-resistant MFA** and
**non-MFA is blocked** (Conditional Access — see the guardrail note below).

| User (Entra UPN) | Role / permission set | What they can do | Reads patient details via |
|---|---|---|---|
| `ith-superadmin@…` | **`ITH-SuperAdmin`** | **Everything** (AdministratorAccess) incl. KMS. | EC2 web UI (path P3) |
| `ith-admin@…` | **`ITH-Admin`** | Scoped to the relevant services (S3, EC2/VPC, CloudWatch, CloudTrail, GuardDuty-read) — **explicitly denied all `kms:*`**. | EC2 web UI (path P3) |
| `ith-s3@…` | **`ITH-S3Reader`** | **Read the S3 bucket only from inside the VPC** (`aws:sourceVpce` condition); denied otherwise. | EC2 web UI (P3) + in-VPC CLI (P4) |

> **All three humans read patient *details* only through the EC2-hosted web app
> (path P3).** No human identity has direct `s3:GetObject` on the sensitive bucket;
> the web app reads S3 with the **EC2 instance role** from inside the VPC.

> ### ⚠️ Non-breaking guardrail
> Per the owner's instruction, **no breaking changes are applied to the live Entra
> tenant**. The Conditional Access (phishing-resistant MFA + non-MFA block) and the
> Entra user/SCIM provisioning are written as Terraform but **left disabled**
> (`enable_entra_changes = false`) and documented as **suggested, not enabled**. The
> AWS-side **Identity Center permission sets are created for real** (inert until
> assigned). See [`docs/identity-and-mfa.md`](docs/identity-and-mfa.md).

---

## 2. What's protected and how (Prevent / Detect / Respond)

**Resource:** two S3 buckets in an **isolated new account** under a dedicated OU.

| Bucket | Contents | Reachable from |
|---|---|---|
| `phi-sensitive-<acct-id>` | full ePHI (tokenized, per-patient KMS) | **only inside the VPC** (4 controlled paths) |
| `phi-deident-<acct-id>` | de-identified / non-sensitive copy | **anywhere in the org** (still org-locked, TLS, KMS) |

**Four controlled paths to the sensitive bucket** (full detail in
[`docs/data-plane-paths.md`](docs/data-plane-paths.md)):

1. **Lambda redactor** — an **S3 Object Lambda Access Point** returns only
   **non-sensitive** fields (the "basic reader").
2. **On-prem Kubernetes** — reaches S3 over **VPC peering** + an S3 **Gateway
   endpoint** (peering's N²/non-transitive scaling limit is documented).
3. **EC2 web app** — EC2 **instance role**, **SSM-only** (no SSH, no key pair); the
   sole human read UI.
4. **`s3` principal direct read** — IAM read **gated on `aws:sourceVpce`** (in-VPC only).

```
                       Microsoft Entra ID  (IdP: phishing-resistant MFA, non-MFA blocked)
                                 │ SCIM + SAML
                                 ▼
                       AWS IAM Identity Center ──> ITH-SuperAdmin / ITH-Admin / ITH-S3Reader
                                 │
   AWS Org o-ncxqr8pp2c          ▼          (SCP: S3 guardrails • RCP: deny S3 outside org)
   ┌─ Management 337066574719 ──── OU: InterviewTakeHome ──── Account: ith-workload ─┐
   │                                                                                  │
   │   VPC (workload, no internet)                          VPC (on-prem)            │
   │   ┌──────────────────────────┐   peering   ┌────────────────────────┐          │
   │   │ EC2 web app (SSM only) ───┼─────────────┤ k8s node (pod role)    │          │
   │   │ Lambda redactor (OLAP)    │             └───────────┬────────────┘          │
   │   │ s3 reader (sourceVpce)    │                         │ S3 Gateway endpoint   │
   │   └─────────────┬────────────┘                         ▼                        │
   │                 ▼  KMS (per-patient CMK)  ┌─ S3 phi-sensitive  (VPC-only) ─┐     │
   │        Interface/Gateway VPC endpoints ──>│  S3 phi-deident   (org-wide)   │     │
   │                                           └────────────────────────────────┘     │
   │   Detect/Respond: CloudTrail • GuardDuty • CloudWatch alarms • SNS               │
   └──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Repository layout

```
InterviewTakeHome/
├── README.md                 ← you are here (page 1 = users + login URL)
├── REQUIREMENTS.md           ← requirement → implementation traceability
├── terraform/
│   ├── 00-org/               ← OU, member account, SCP, RCP   (mgmt account)
│   ├── 10-identity/          ← Identity Center permission sets (real) + Entra/CA (doc-only)
│   └── 20-workload/          ← KMS, S3×2, VPC×2, peering, endpoints, SGs, EC2, Lambda, detect
├── app/
│   ├── webapp/               ← EC2 web UI (the human read path)
│   ├── lambda-redactor/      ← Object Lambda transform → non-sensitive
│   └── tokenizer/            ← vaultless tokenization (key-epoch tagged)
├── data/                     ← Synthea synthetic patients (tokenized)
├── diagrams/                 ← editable draw.io diagrams ([NN] component IDs)
├── docs/                     ← design, controls map, tradeoffs, runbooks
└── scripts/                  ← data-gen + teardown
```

---

## 4. Deploy / validate

> Prereqs: Terraform ≥ 1.14, AWS SSO profile with **management-account** admin
> (`ith-mgmt`), `az` logged into the tenant. Region `ap-southeast-1`.

```bash
# 1) Org plumbing: new OU + member account + SCP + RCP   (management account)
cd terraform/00-org && terraform init && terraform apply

# 2) Workload: KMS, S3, VPCs, peering, endpoints, SGs, EC2, Lambda, CloudTrail, GuardDuty, alarms
cd ../20-workload && terraform init && terraform apply

# 3) Identity: Identity Center permission sets (real). Entra/CA stay disabled by default.
cd ../10-identity && terraform init && terraform apply
```

Validate-only (no changes): `terraform validate && terraform plan` in each stack.

**Teardown** (run after verdict): [`scripts/teardown.md`](scripts/teardown.md) — note
the AWS **90-day account-closure** window.

---

## 5. Documentation index

| Doc | What |
|---|---|
| [`REQUIREMENTS.md`](REQUIREMENTS.md) | requirement → implementation matrix |
| [`docs/design.md`](docs/design.md) | full Prevent/Detect/Respond design + failure modes |
| [`docs/data-plane-paths.md`](docs/data-plane-paths.md) | the 4 paths + 2 buckets, in detail |
| [`docs/identity-and-mfa.md`](docs/identity-and-mfa.md) | Entra ↔ Identity Center, phishing-resistant MFA |
| [`docs/encryption-and-tokenization.md`](docs/encryption-and-tokenization.md) | per-patient KMS + vaultless tokens |
| [`docs/detection-and-response.md`](docs/detection-and-response.md) | CloudTrail/GuardDuty/alarms catalog |
| [`docs/tradeoffs-and-out-of-scope.md`](docs/tradeoffs-and-out-of-scope.md) | cost vs compliance, peering, VPC endpoints, out-of-scope |
| [`diagrams/`](diagrams/) | editable draw.io architecture diagrams |

---

*Synthetic data only (Synthea) — contains no real PHI. Built for an interview; all
resources are isolated and will be destroyed after verdict.*

# Requirements Traceability Matrix

> Single source of truth for this take-home. Every requirement the interviewer gave
> (and every clarification since) is listed here with: the literal ask, how this
> build interprets it, **how it is satisfied**, and status. Read this top-to-bottom
> to grade the submission against the brief.

**Scenario:** Secure a sensitive resource (an **S3 bucket of ePHI / health data**) in
the cloud — preventing, detecting, and responding to unauthorized access, and holding
up when something fails. Everything is **Infrastructure-as-Code (Terraform)** and
**actually deployed** to isolated accounts, then torn down after verdict.

---

## 0. Live environment facts (discovered, not assumed)

| Thing | Value |
|---|---|
| AWS Organization | `o-ncxqr8pp2c` (FeatureSet ALL) |
| Management account | `337066574719` ("Managment", dylanheathsmart@gmail.com) |
| Org root | `r-33e3` — **both SCP and RCP policy types ENABLED** |
| Identity Center instance | `ssoins-46812a8af28769cf`, identity store `d-96677e53fe`, in mgmt acct |
| Identity source | **External IdP = Entra ID**, users **SCIM-provisioned** (`scim.aws.com`) |
| AWS access portal (login URL) | **https://d-96677e53fe.awsapps.com/start/** |
| Entra tenant | `delicatehug.com` (`16a0c46e-e66c-4544-acb5-237c7d29e036`) |
| Entra licensing | **AAD_PREMIUM (P1) present** → Conditional Access + auth strengths available |
| New isolated OU (created) | `InterviewTakeHome` (under root) |
| New member account (created) | `ith-workload` (dylanheathsmart+ith-workload@gmail.com) |
| Region | `ap-southeast-1` (Singapore) |

> **Isolation discipline:** SCP/RCP attach **only** to the new `InterviewTakeHome` OU.
> Nothing touches the user's existing accounts (DSOAR-*, Cyber Champion) or their own identity.
>
> ### ⚠️ Non-breaking guardrail (owner instruction)
> **No breaking changes to the live Entra tenant or AWS org.** Concretely:
> - **AWS** — only **additive, isolated** resources are deployed for real: the new OU,
>   the new member account, workload resources in that account, and SCP/RCP attached
>   **only to the new OU**. CloudTrail/GuardDuty are **account-level** (not org-wide
>   delegated admin), so existing accounts are untouched.
> - **Entra** — Conditional Access (phishing-resistant MFA, non-MFA block) and the 3
>   Entra users + SCIM provisioning are **written as IaC but NOT applied** (behind
>   `var.enable_entra_changes`, default `false`). They are **documented as suggested,
>   not enabled**, so the live `delicatehug.com` tenant and its 7 existing CA policies
>   are not changed. The **AWS Identity Center permission sets** *are* created for real
>   (inert until assigned); the **assignments** to the 3 users are documented-not-applied
>   because they depend on the (not-provisioned) Entra users.

---

## 1. Hard requirements (must-have)

| # | Requirement (as given) | Interpretation & how satisfied | Status |
|---|---|---|---|
| R1 | **S3 bucket with sensitive data** | Primary bucket `phi-sensitive-<acct-id>` holds ePHI objects (Synthea). SSE-KMS, BPA on, TLS-only, VPC-locked. | ⬜ |
| R2 | **Phishing-resistant MFA** for admins via the **IdP** | Entra Conditional Access requires **authentication strength = Phishing-resistant MFA** (`00000000-0000-0000-0000-000000000004`, FIDO2/passkey/WHfB/CBA) for the interview-admins group on the AWS app. **IaC written; left disabled (`enable_entra_changes=false`) to avoid changing the live tenant — documented as suggested.** | 📝 doc-only |
| R3 | **Non-MFA blocked** | Entra CA: block sign-in that does not satisfy the phishing-resistant strength (no fallback to password/SMS). Legacy auth already blocked tenant-wide. **IaC written; left disabled — documented as suggested.** | 📝 doc-only |
| R4 | **Alerting** / "alarms for everything" | SNS topic + CloudWatch alarms: root usage, console-without-MFA, unauthorized API, IAM/policy changes, S3 policy changes, KMS disable/scheduled-deletion, CloudTrail tamper, GuardDuty high-sev findings, **AssumeRole from unexpected IP (R12)**, S3 4xx/AccessDenied spikes, SG changes. | ⬜ |
| R5 | **Everything is IaC** | 100% Terraform: `00-org`, `10-identity`, `20-workload`. No console clicks for resources. | ⬜ |
| R6 | **One management account + one OU + one account inside the OU** | Mgmt `337066574719` → OU `InterviewTakeHome` → member `ith-workload` (created by Terraform `aws_organizations_account`). | ⬜ |
| R7 | **S3 inter-account naming suffix** | Bucket names suffixed with the **account ID** (globally-unique, account-traceable): `phi-sensitive-<acct>`, `phi-deident-<acct>`. | ⬜ |
| R8 | **S3 must require an org-level SCP** | SCP on the OU **denies** `s3:*` unless requests meet org guardrails (deny non-KMS PutObject, deny disabling BPA/encryption, deny bucket deletion, require TLS). | ⬜ |
| R9 | **RCP must stop S3 to outer organization** | Resource Control Policy on the OU **denies** S3 access unless `aws:PrincipalOrgID == o-ncxqr8pp2c` — blocks any principal outside this org (incl. confused-deputy / cross-account). | ⬜ |
| R10 | **IdP requires phishing-resistant MFA for admins** | = R2 (Entra is the IdP; federation already exists, reused). **doc-only** (see guardrail). | 📝 doc-only |
| R11 | **CloudTrail + GuardDuty enabled** | Org/account CloudTrail (multi-region, log-file validation, KMS-encrypted, → dedicated log bucket) + GuardDuty detector with all features. | ⬜ |
| R12 | **Role assumptions must have IP-based alerting** | EventBridge rule on `AssumeRole`/`AssumeRoleWithSAML` → Lambda evaluates `sourceIPAddress` vs allow-list CIDRs → SNS alert on out-of-range. Backstopped by a CloudTrail metric-filter alarm. | ⬜ |
| R13 | **3 users**, documented on README page 1 with login URL | `super-admin` (all), `admin` (scoped services, **no KMS**), `s3` (read S3 **only when inside a VPC**). **Identity Center permission sets created for real**; Entra users + assignments **doc-only** (guardrail). Login URL on README p.1. | 🟡 perm-sets real / users doc-only |
| R14 | **Example health data**, Synthea, **≥5 patient records** | Synthea generates ≥5 synthetic patients (FHIR/CSV). Sensitive fields **vaultless-tokenized** before upload. | ⬜ |
| R15 | **S3 must use KMS, "per person"** → **per-patient CMK** | One **customer-managed KMS key per patient**; object encrypted under its patient's CMK; S3 default encryption + bucket-key. **Cost-vs-compliance tradeoff documented** (see §4). | ⬜ |
| R16 | **4 paths to the bucket** | See §2. Lambda (Object Lambda redactor), on-prem K8s (VPC peering), EC2 web app (instance role, SSM-only), and the `s3` principal direct-read gated on `aws:sourceVpce`. | ⬜ |
| R17 | **Security group as allow + port** | All data-plane SGs use **SG-as-source** rules (ingress `source_security_group_id`, not CIDR) on specific ports — e.g. web-app SG ← ALB/SSM, endpoint SG ← app SG:443. | ⬜ |
| R18 | **Vaultless tokenization** of the S3 data | Deterministic, **key-epoch-tagged** tokens (no token vault). DEK per epoch from KMS; old epochs retained for decrypt; rotate-forward without mass re-tokenization. | ⬜ |
| R19 | **Diagrams + readable documentation** (utmost importance) | Editable **draw.io** diagrams (org, data-plane 4-paths, identity/MFA, detect/respond) + `[NN]` component IDs linked to per-control docs (HippaTest convention). | ⬜ |

## 1a. Clarifications added mid-flight

| # | Added requirement | How satisfied | Status |
|---|---|---|---|
| C1 | **All 3 admins must read details only via the EC2 web UI** | Sensitive-bucket policy gives **no human identity** direct `GetObject`; humans hit the EC2-hosted web app, which reads S3 via the **EC2 instance role** from inside the VPC. | ⬜ |
| C2 | **Lambda access point = "basic reader"** that **transforms data to non-sensitive** | **S3 Object Lambda Access Point** invokes a redactor Lambda that strips/masks PHI and returns **de-identified** fields only. | ⬜ |
| C3 | **No EC2 login — use SSM auth** | EC2 has **no key pair, no SSH ingress**; access via **SSM Session Manager** only (instance role has SSM core; SG has no port-22). | ⬜ |
| C4 | **2nd bucket** = copy of the data but **viewable outside the VPC** | `phi-deident-<acct>` holds the de-identified/tokenized copy; **no VPC condition** (readable anywhere in the org) but still org-locked (RCP), TLS-only, KMS-encrypted. Demonstrates the VPC-condition delta. | ⬜ |

---

## 2. The four access paths to the (sensitive) bucket

| Path | Caller | Network route | Authz | Returns |
|---|---|---|---|---|
| **P1 — Lambda redactor** | "basic reader" automation | invoke **S3 Object Lambda Access Point** | OLAP supporting access point + Lambda exec role | **non-sensitive** (redacted) fields only (C2) |
| **P2 — On-prem Kubernetes** | pod in "on-prem" cluster | **VPC peering** on-prem VPC → workload VPC → **S3 Gateway endpoint** | pod/node IAM role, `aws:sourceVpce` | full object (in-cluster use) |
| **P3 — EC2 web app** | human admins (all 3) | browser → EC2 web app (SSM-managed host) → **S3 interface/gateway endpoint** | **EC2 instance role**; humans never touch S3 directly (C1) | rendered patient details |
| **P4 — `s3` principal direct** | the `s3` identity | CLI/SDK **from inside the VPC** only | IAM + bucket policy `aws:sourceVpce == <workload vpce>` | full object, VPC-gated (R13) |

> **Peering scalability caveat (documented in `docs/`):** VPC peering is
> **non-transitive** and **N²** — every new VPC needing the data tier adds a new
> peering + route-table entries on both sides; it doesn't scale past a handful of
> VPCs. Transit Gateway (or PrivateLink to a single endpoint service) is the scalable
> successor. Peering is used here deliberately to match the brief and to make the
> tradeoff concrete.

---

## 3. Out of scope (noted as useful, intentionally excluded)

Called out so the interviewer sees these were *considered*, not missed:

- **AWS Control Tower** — would automate landing-zone/guardrails; overkill for a 1-OU/1-account demo (we do the org plumbing by hand to show it).
- **Backup & recovery (AWS Backup)** — production ePHI needs immutable, cross-region, tested restores; out of scope for an access-control demo.
- **ALB** — no public web tier in scope; EC2 app reached via SSM, not internet ingress.
- **Application Recovery Controller (ARC)** — multi-region failover routing; no HA region here.
- **Root-account usage alerting** — included conceptually in alarms list but root is the org mgmt account we don't own end-to-end; we alarm what we can in the workload account.
- **Centralized logging** (org-wide log-archive account) — we keep CloudTrail/Config in the workload account for the demo; production would ship to a dedicated Log Archive account.
- **Amazon Inspector** — runtime/SCA vuln scanning of shared libraries & EC2/containers; valuable but orthogonal to the access-control story.

**VPC endpoint note:** requiring all S3 access through **VPC endpoints is operational
overhead** (extra resources, endpoint policies, the "silent public-endpoint fallback"
trap) — but for **sensitive data it is a strong control**: it keeps traffic on the AWS
backbone and lets the bucket policy gate on `aws:sourceVpce`, which is the mechanism
behind P3/P4 and the VPC-only property of the sensitive bucket.

---

## 4. Documented tradeoffs

- **Per-patient KMS CMK (R15) — cost vs compliance.** *Compliance upside:* hard
  cryptographic blast-radius isolation per data subject; disable one key → exactly one
  patient's data goes dark (a per-subject "right to erasure"/incident lever); per-key
  CloudTrail = per-patient access audit. *Cost/ops downside:* **$1/key/month** + API
  costs, and AWS soft limit ~100k keys/region; key sprawl and lifecycle become real
  ops. *Verdict for real systems:* prefer **one CMK + per-patient data keys / encryption
  context** (same audit & isolation story, no key sprawl). We implement the literal
  per-patient-CMK ask here and document this as the recommended production alternative.
- **Vaultless tokenization (R18).** No token vault to run/secure/scale; tokens are
  self-describing (carry key epoch). Rotate by minting a new DEK epoch for new writes
  and retaining old epochs for reads — no mass re-tokenization. Tradeoff: tokens are
  deterministic per epoch (enables join/equality) which is a re-identification surface
  vs. fully random vault tokens — acceptable for de-identified analytics, documented.
- **VPC peering (R16/P2)** — see §2 caveat (N², non-transitive; TGW is the successor).

---

## 5. Deliverables checklist

- [ ] `terraform/00-org` — OU, member account, SCP, RCP
- [ ] `terraform/10-identity` — Entra users/group, CA (phishing-resistant + non-MFA block), Identity Center permission sets + assignments
- [ ] `terraform/20-workload` — KMS, 2× S3, VPC×2 + peering + endpoints, SGs, EC2(SSM), Lambda+OLAP, on-prem node, CloudTrail, GuardDuty, alarms, SNS
- [ ] `app/` — web app, redactor Lambda, vaultless tokenizer
- [ ] `data/` — Synthea ≥5 patients, tokenized
- [ ] `diagrams/` — draw.io (org / data-plane / identity / detect-respond) with `[NN]` IDs
- [ ] `docs/` — design, per-control mapping, cost/compliance, peering, VPC-endpoint, out-of-scope
- [ ] `README.md` — page 1: 3 users + login URL; how to deploy/validate
- [ ] `scripts/teardown.*` — full destroy + account-close runbook (run after verdict)

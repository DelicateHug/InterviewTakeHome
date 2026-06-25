# Architecture diagrams & component-ID index

Editable **draw.io** diagrams for the AWS + Entra secure-S3 take-home. They satisfy
**R19** (diagrams + readable docs) and give every component a stable `[NN]` ID so the
docs and controls can reference exact parts of the system.

- **File:** [`ith-architecture.drawio`](ith-architecture.drawio) — a single multi-page
  file with **4 tabs** (pages).
- **Open it:** in VS Code with the **Draw.io Integration** extension
  (`hediet.vscode-drawio`) it renders inline and edits in place. If it opens as raw
  XML, right-click the file → *Open With… → Draw.io*. After installing the extension
  you may need to reload the window.

```bash
code --list-extensions | grep -i drawio || code --install-extension hediet.vscode-drawio
```

## The 4 pages

| Page (tab) | Scope | Covers |
|---|---|---|
| **1. Org & Guardrails** | AWS Org → mgmt account → OU → member account; SCP + RCP attached to the OU only | R6, R8, R9 |
| **2. Data Plane (4 paths)** | Workload VPC (no internet) + on-prem VPC + peering; 2 buckets; the 4 read paths; endpoints; SGs; per-patient KMS | R1, R7, R15, R16, R17, C1–C4 |
| **3. Identity & MFA** | Entra (IdP) → IAM Identity Center → 3 permission sets; Conditional Access (phishing-resistant MFA, written-but-disabled) | R2, R3, R10, R13 |
| **4. Detect & Respond** | CloudTrail → CW Logs → 9 alarm metric-filters → SNS; GuardDuty → EventBridge → SNS; AssumeRole IP-alerter; response levers | R4, R11, R12 |

## ID scheme

IDs are **reserved per page in contiguous blocks** so they never collide and never get
renumbered. New components take the **next free number in that page's block**; never
renumber an existing component.

- Page 1: `[01]–[09]`
- Page 2: `[10]–[39]`
- Page 3: `[40]–[49]`
- Page 4: `[50]–[64]`

## ID → component → requirement → controls doc

> "Controls doc" is the `docs/*.md` (or root `*.md`) file that describes the controls /
> design for that component. Several docs are the canonical targets named in the repo
> [`README.md`](../README.md) §5 and [`REQUIREMENTS.md`](../REQUIREMENTS.md).

### Page 1 — Org & Guardrails

| ID | Component | Req | Controls doc |
|---|---|---|---|
| `[01]` | AWS Organization `o-ncxqr8pp2c` (FeatureSet ALL) | R6 | [`docs/design.md`](../docs/design.md) |
| `[02]` | Org root `r-33e3` — SCP + RCP policy types enabled | R8, R9 | [`docs/design.md`](../docs/design.md) |
| `[03]` | Management account `337066574719` | R6 | [`docs/design.md`](../docs/design.md) |
| `[04]` | OU `InterviewTakeHome` `ou-33e3-5p8xygxw` (sole attach target) | R6 | [`docs/design.md`](../docs/design.md) |
| `[05]` | Member account `ith-workload` `118821711925` | R6 | [`docs/design.md`](../docs/design.md) |
| `[06]` | SCP `ith-scp-s3-guardrails` (TLS req, SSE-KMS on phi-* puts, protect BPA) | R8 | [`docs/design.md`](../docs/design.md) |
| `[07]` | RCP `ith-rcp-s3-org-only` (deny S3 to principals outside org) | R9 | [`docs/design.md`](../docs/design.md) |

### Page 2 — Data Plane

| ID | Component | Req | Controls doc |
|---|---|---|---|
| `[10]` | On-prem VPC `192.168.0.0/16` (has IGW) | R16 | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[11]` | On-prem k3s node `EC2 i-0a3dfcb0…` (pod/node IAM role) | R16 (P2) | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[12]` | On-prem node SG (SG-as-source for endpoint SG ingress) | R17 | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[13]` | Workload VPC `10.20.0.0/16` (no internet) | R16 | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[14]` | Lambda `ith-redactor` (IAM Function URL) — redactor | R16 (P1), C2 | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[15]` | EC2 web app `i-004a7375…` (SSM-only, no SSH) — sole human read | R16 (P3), C1, C3 | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[16]` | `s3` reader role — direct read gated on `aws:sourceVpce` | R16 (P4), R13 | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[17]` | App / web SG (SG-as-source) | R17 | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[18]` | S3 **Gateway** endpoint `vpce-0d4239508…` (in-VPC only) | R16 (P3/P4) | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[19]` | S3 **Interface** endpoint `vpce-000ca0be9…` (reachable across peering) | R16 (P2) | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[20]` | S3 `phi-sensitive-118821711925` (VPC-locked, full ePHI) | R1, R7, R15 | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[21]` | Endpoints SG — ingress 443 from `[17]` app SG and `[12]` on-prem SG | R17 | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[22]` | Interface endpoints (ssm/ssmmessages/ec2messages/sts/kms/logs) | C3, R11 | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[23]` | S3 Object Lambda Access Point `ith-sensitive-ap` | C2 | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[24]` | KMS per-patient CMKs `alias/ith/patient/*` | R15 | [`docs/encryption-and-tokenization.md`](../docs/encryption-and-tokenization.md) |
| `[25]` | S3 `phi-deident-118821711925` (org-wide, de-identified copy) | R7, C4 | [`docs/data-plane-paths.md`](../docs/data-plane-paths.md) |
| `[26]` | VPC peering (on-prem ↔ workload; non-transitive / N²) | R16 (P2) | [`docs/tradeoffs-and-out-of-scope.md`](../docs/tradeoffs-and-out-of-scope.md) |

### Page 3 — Identity & MFA

| ID | Component | Req | Controls doc |
|---|---|---|---|
| `[40]` | Microsoft Entra ID (IdP), tenant `delicatehug.com`, P1 | R10 | [`docs/identity-and-mfa.md`](../docs/identity-and-mfa.md) |
| `[41]` | Conditional Access policy (phishing-resistant MFA; non-MFA block) | R2, R3 | [`docs/identity-and-mfa.md`](../docs/identity-and-mfa.md) |
| `[42]` | AWS IAM Identity Center `ssoins-46812a8…` (login URL `d-96677e53fe`) | R13 | [`docs/identity-and-mfa.md`](../docs/identity-and-mfa.md) |
| `[43]` | Permission sets container (created real; assignments doc-only) | R13 | [`docs/identity-and-mfa.md`](../docs/identity-and-mfa.md) |
| `[44]` | Permission set `ITH-SuperAdmin` (everything, incl. KMS) | R13 | [`docs/identity-and-mfa.md`](../docs/identity-and-mfa.md) |
| `[45]` | Permission set `ITH-Admin` (scoped services, **deny `kms:*`**) | R13 | [`docs/identity-and-mfa.md`](../docs/identity-and-mfa.md) |
| `[46]` | Permission set `ITH-S3Reader` (S3 read only when `aws:sourceVpce` matches) | R13 | [`docs/identity-and-mfa.md`](../docs/identity-and-mfa.md) |

### Page 4 — Detect & Respond

| ID | Component | Req | Controls doc |
|---|---|---|---|
| `[50]` | CloudTrail `ith-trail` (multi-region, log validation, KMS, S3 data events) | R11 | [`docs/detection-and-response.md`](../docs/detection-and-response.md) |
| `[51]` | CloudWatch Logs `/ith/cloudtrail` | R4, R11 | [`docs/detection-and-response.md`](../docs/detection-and-response.md) |
| `[52]` | 9 metric-filter alarms (root, no-MFA, IAM/policy, KMS, tamper, AssumeRole-IP, …) | R4 | [`docs/detection-and-response.md`](../docs/detection-and-response.md) |
| `[53]` | GuardDuty detector (all features) | R11 | [`docs/detection-and-response.md`](../docs/detection-and-response.md) |
| `[54]` | EventBridge rule — GuardDuty finding severity ≥ 4 | R4, R11 | [`docs/detection-and-response.md`](../docs/detection-and-response.md) |
| `[55]` | SNS `ith-security-alerts` (KMS-encrypted, email) | R4 | [`docs/detection-and-response.md`](../docs/detection-and-response.md) |
| `[56]` | EventBridge rule — `sts:AssumeRole*` | R12 | [`docs/detection-and-response.md`](../docs/detection-and-response.md) |
| `[57]` | Lambda `ith-ip-alerter` (sourceIP vs allow-list → unexpected-IP alert) | R12 | [`docs/detection-and-response.md`](../docs/detection-and-response.md) |
| `[58]` | Response levers group (assume-breach) | R4 | [`docs/detection-and-response.md`](../docs/detection-and-response.md) |
| `[59]` | Disable a per-patient KMS key (one patient goes dark) | R15 | [`docs/encryption-and-tokenization.md`](../docs/encryption-and-tokenization.md) |
| `[60]` | Revoke credentials | R4 | [`docs/detection-and-response.md`](../docs/detection-and-response.md) |
| `[61]` | Quarantine security group | R4, R17 | [`docs/detection-and-response.md`](../docs/detection-and-response.md) |

## Adding a component

1. Give it the **next free ID in that page's reserved block** (do not reuse or
   renumber). If a page fills its block, extend the block — don't borrow another
   page's range.
2. Add it to the table above (component, req, controls doc).
3. Reference the `[NN]` from the owning `docs/*.md` so "what protects `[NN]`?" stays
   traceable end-to-end.

## Layout conventions (so edits stay readable)

- One primary flow per page (Page 1/3 top→bottom; Page 2/4 left→right).
- Orthogonal edges with explicit waypoints routed in the empty margins.
- Color tiers: **blue** compute, **green** the controlled path / SNS sink,
  **orange/yellow** network & VPC endpoints, **purple** KMS / org-policy,
  **red** data & security boundaries.
- Cylinders for S3 buckets; dashed containers for VPCs / OUs / groups.
- A legend text box on every page restates specifics so no edge has to carry them.

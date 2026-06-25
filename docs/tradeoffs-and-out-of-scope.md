# Tradeoffs, Out-of-Scope, and the VPC-Endpoint Note

> **Summary.** This deployment makes a few deliberate, defensible trades: per-patient CMKs (audit clarity over cost/sprawl), vaultless deterministic tokenization (equality joins over per-occurrence randomness), and VPC peering (matches the brief, but does not scale). Everything below is **as-built** and live. A few capabilities were considered and consciously left out of scope; each is listed with the one thing it would add.

See also: [REQUIREMENTS.md](../REQUIREMENTS.md) for the R1..R19 / C1..C4 requirement and control ids referenced throughout.

---

## At a glance

| Decision | What we did | The cost | Why it's worth it |
|---|---|---|---|
| **Per-patient CMK** (R15) | One customer-managed KMS key per patient (7 keys) | ~$1/key/month, ~100k keys/region soft limit, key sprawl | Per-subject crypto blast-radius + per-key CloudTrail audit |
| **Vaultless tokenization** (R18) | Deterministic AES-256-SIV tokens, no vault | Deterministic output leaks equality | Reversible, joinable, no vault to breach or run |
| **VPC peering** | Workload VPC ↔ on-prem VPC, routes both ways | Non-transitive, N² connections | Concrete, simple, matches the brief |
| **S3-via-VPC-endpoint gate** | `aws:sourceVpce` required on the sensitive bucket | Extra resources + the silent public-endpoint trap | Traffic stays on the AWS backbone; it *is* the bucket's access control |

---

## 1. Per-patient CMK: cost vs compliance (R15)

The brief asks for encryption "per person," so we implemented it literally: **one customer-managed CMK per patient** (7 patients), aliased `alias/ith/patient/<12-hex>`, with rotation enabled and a 7-day deletion window. Each key's policy grants the account root `kms:*` plus the four reader roles `Decrypt` / `GenerateDataKey*` / `DescribeKey`. Every object in the sensitive bucket is SSE-KMS encrypted under its patient's key.

**The benefit — a tight crypto blast-radius.** Disable one key and **exactly one patient goes dark**; nobody else is affected. Each key also gets its own CloudTrail trail of decrypts, so "who read this patient's data" is answerable per subject.

**The cost — sprawl.** Customer-managed keys run about **$1/key/month**, there is a **~100k keys/region soft limit**, and managing one key per subject does not scale to a real patient population. At hospital scale this is thousands of dollars/month in keys alone, plus the operational weight of tracking, rotating, and auditing each one.

**Recommended production alternative.** Use **one CMK plus per-patient data keys / KMS encryption context** (e.g. `patient_id` in the encryption context). This preserves the same per-subject audit trail and isolation — you can still answer "who decrypted patient X" and still scope access per subject — **without the key sprawl**. We built the literal per-patient-CMK as asked and document the trade here so the production path is explicit.

Related keys in the deployment: `alias/ith/deident` (the de-identified bucket) and `alias/ith/logs` (CloudTrail + CloudWatch Logs + SNS).

---

## 2. Vaultless tokenization: the determinism tradeoff (R18)

Sensitive fields (name, SSN, MRN, phone, email, address line, postal code, birth date) are replaced **before** they ever land in S3 with tokens of the form:

```
tok:v{epoch}:{base64url(AES-SIV(value, AAD=fieldname))}
```

There is **no token vault**. The token is derived cryptographically; `detokenize()` simply decrypts it with the epoch key. This removes a whole class of risk — there is no lookup database to breach, replicate, or keep available — but it forces one specific tradeoff.

**The tradeoff: deterministic output.** AES-256-SIV is deterministic, so **the same value in the same field always produces the same token**.

| You gain | You give up |
|---|---|
| **Equality joins** — token equality means value equality, so you can join/group/dedupe on tokenized fields | **Per-occurrence randomness** — a deterministic token reveals that two records share a value, even without detokenizing |
| **Authenticated reversibility** — SIV is authenticated; tampered tokens fail to decrypt | Protection against frequency analysis on low-cardinality fields |

For this use case the join capability is the point, and the determinism is contained: tokens live only in an org-locked, endpoint-gated bucket, and the de-identified view (below) drops the fields entirely. If a field needed equality *hidden*, a non-deterministic (randomized) mode would be the alternative — at the cost of joinability.

**Key handling.** Epoch DEKs come from HKDF over a demo master in the script today; in **production each epoch DEK comes from `kms:GenerateDataKey`**, with the wrapped DEK stored alongside its epoch id.

**Rotate-forward, not re-tokenize.** Tokens are **epoch-tagged**, so rotation is cheap: mint a new epoch for new writes, keep old epoch DEKs around to read old tokens, and retire old epochs lazily. There is **no mass re-tokenization** event.

**Defense in depth.** Field tokenization is layered *under* per-patient SSE-KMS at rest, and the de-identified copy goes further still (HIPAA Safe-Harbor style: `pseudo_id` = keyed HMAC, age band instead of DOB, state instead of address) — see [P1/de-identification details](#) in the path documentation.

---

## 3. VPC peering: non-transitive and N² (Transit Gateway is the successor)

The workload VPC (`10.20.0.0/16`, fully private — no IGW, no NAT) reaches the on-prem VPC (`192.168.0.0/16`) over a **VPC peering connection** with routes configured both ways. This is how the on-prem k3s node reads the sensitive bucket across the peering via the S3 **interface** endpoint.

Peering was chosen **deliberately** to match the brief and to make the scalability tradeoff concrete — but it has two well-known limits:

- **Non-transitive.** If VPC A peers with B, and B peers with C, **A cannot reach C** through B. Every pair that needs to talk needs its own peering.
- **N² growth.** Each new VPC that needs the data tier adds **one more peering connection and route-table entries on both sides**. With *n* VPCs that all need to talk, you trend toward *n(n−1)/2* connections. This does not scale past a handful of VPCs.

**The scalable successor: Transit Gateway** (a hub-and-spoke router — each VPC attaches once, TGW handles transitive routing), or **PrivateLink to a single endpoint service** if the goal is to expose just the data tier rather than full VPC-to-VPC routing. Either replaces the N² mesh with linear growth.

---

## 4. The VPC-endpoint note: overhead, but a strong control — and the silent fallback trap

All S3 access to the sensitive bucket is forced through **VPC endpoints**. The bucket policy denies `GetObject` / `GetObjectVersion` / `ListBucket` unless the request arrives via an approved `aws:sourceVpce`:

- **`vpce-0d4239508db2903d7`** — the S3 **gateway** endpoint, used by in-VPC clients (the EC2 web app, C1).
- **`vpce-000ca0be99fa5595c`** — the S3 **interface** endpoint, so the **peered on-prem VPC** can reach S3 over the peering (gateway endpoints are *not* reachable across peering, which is exactly why the interface endpoint exists).

This is the mechanism behind the bucket's access control: a human laptop with no `vpce` is **denied** (verified), which is what forces humans onto the EC2 web app (C1). It also keeps PHI traffic **on the AWS backbone** instead of traversing the public internet.

**The honest cost — operational overhead.** Endpoints are extra resources to provision, secure (endpoint policies), and reason about. Interface endpoints carry an hourly + per-GB charge. And there is one trap worth calling out:

> ### The silent public-endpoint fallback trap
> If an interface endpoint has **private DNS enabled** but is misconfigured or missing for a given service, or if a client is simply outside the VPC, S3 SDK/CLI calls **silently fall back to the public S3 endpoint** and "just work" — quietly bypassing the `aws:sourceVpce` control you thought was enforcing things. The request succeeds, no error is raised, and the intended network boundary is gone.
>
> Two things guard against this here: (1) the bucket policy **denies by default** unless a known `vpce` is present, so a public-endpoint request is rejected rather than silently allowed; and (2) the on-prem interface endpoint runs with **private DNS disabled** and is addressed by its explicit wildcard DNS name (strip the leading `*.` from `*.vpce-...` to use it as the endpoint URL), making the endpoint path explicit rather than implicit.

**Verdict:** for sensitive data the overhead is worth it — endpoints are not just plumbing here, they *are* the access-control gate. See the [network and endpoints documentation](#) for the full endpoint inventory (gateway S3, interface S3, plus ssm/ssmmessages/ec2messages/sts/kms/logs so the workload VPC needs no internet).

---

## 5. Out of scope (considered, not missed)

The following were evaluated and consciously deferred to keep this take-home focused on the core data-protection problem. Each line states the single thing it would add.

| Item | What it would add |
|---|---|
| **AWS Control Tower** | A managed landing-zone with guardrails and account factory, instead of the hand-built OU + SCP/RCP setup. |
| **AWS Backup / recovery** | Scheduled, policy-driven backups and point-in-time recovery for the data (we rely on S3 versioning today). |
| **Application Load Balancer (ALB)** | A managed, scalable HTTPS front door for the web app, replacing SSM port-forwarding to a single instance. |
| **Application Recovery Controller (ARC)** | Routing-control-based failover and readiness checks for multi-AZ/region resilience. |
| **Dedicated root-usage alerting** | Org-wide root-account-activity detection from the management account (we alarm on root-usage within the workload account via the CloudWatch metric filter). |
| **Centralized logging (Log Archive account)** | A dedicated, immutable log-archive account aggregating logs across all accounts, vs. logs staying in the workload account. |
| **Amazon Inspector** | Continuous vulnerability scanning of EC2/containers for CVEs and unintended network exposure. |

> **What *is* in scope and built:** CloudTrail (multi-region, log-file validation, KMS-encrypted, with S3 data events on both buckets), GuardDuty → EventBridge → SNS, nine CloudWatch metric-filter alarms on the trail, and EventBridge-driven role-assumption-IP alerting. See the [detection and response documentation](#) for details.

---

## Cross-references

- [REQUIREMENTS.md](../REQUIREMENTS.md) — requirement ids R1..R19 and controls C1..C4.
- Sibling docs in this folder cover the four read paths (P1–P4), networking/endpoints, KMS, and detection/response in detail.

# The 4 Paths + 2 Buckets

> **Summary:** All ePHI lives in one VPC-locked bucket reachable by four deliberately different consumers; a second, org-wide bucket holds only de-identified data. This doc explains both buckets and walks each of the four read paths hop by hop, including the exact bucket-policy logic that gates them.

Related docs: [Network & VPC endpoints](network.md) · [KMS & per-patient keys](kms.md) · [Tokenization (R18)](tokenization.md) · [Identity & access](identity.md) · [Detection & response](detection.md) · [Requirements](../REQUIREMENTS.md)

---

## The two buckets

We run two PHI buckets with opposite reachability on purpose. The split is the core of the data-plane design: raw data is pinned to the network, de-identified data is pinned to the org.

| | `phi-sensitive-118821711925` | `phi-deident-118821711925` |
|---|---|---|
| **Contents** | Full tokenized ePHI, all 7 patients | De-identified copy (HIPAA Safe-Harbor style) |
| **Encryption at rest** | SSE-KMS, **per-patient CMK** on each object ([R15](../REQUIREMENTS.md)) | SSE-KMS, single `alias/ith/deident` CMK |
| **Reachable from** | **Only inside the workload VPC** (via its endpoints) or a same-account access point | **Anywhere in the org** (no VPC condition) |
| **TLS-only** | Yes | Yes |
| **Org-locked** | Yes | Yes |
| **Public access** | Block Public Access ON | Block Public Access ON |
| **Versioning** | On | — |
| **Requirement** | [C1](../REQUIREMENTS.md), [R7](../REQUIREMENTS.md) | [C4](../REQUIREMENTS.md) (bucket 2) |

A third bucket, `ith-cloudtrail-118821711925`, holds CloudTrail logs (SSE-KMS with `alias/ith/logs`) and is covered in [detection.md](detection.md).

### Bucket 1 — VPC-locked sensitive

`phi-sensitive-118821711925` is the only place raw (tokenized) ePHI lives. Its bucket policy enforces, in order:

1. **Deny insecure transport** — `aws:SecureTransport = false` is denied.
2. **Deny outside-org** — principal must belong to org `o-ncxqr8pp2c`.
3. **Deny reads unless on an approved network path.** `GetObject` / `GetObjectVersion` / `ListBucket` are denied **unless** one of:
   - `aws:sourceVpce` is `vpce-0d4239508db2903d7` (the S3 **gateway** endpoint), **or**
   - `aws:sourceVpce` is `vpce-000ca0be99fa5595c` (the S3 **interface** endpoint), **or**
   - the request arrives **via a same-account access point** (`s3:DataAccessPointAccount = 118821711925`).

   AWS service callers are excluded from this deny.
4. **Allow same-account access-point delegation** — so the access point in path P1 can be the front door.

**Net effect:** a human laptop with no `vpce` is **DENIED** (verified). That single fact is why humans cannot hit the bucket directly and must go through the EC2 web app — see [path P3 / C1](#p3--ec2-web-app--the-only-human-path-c1).

### Bucket 2 — org-wide de-identified

`phi-deident-118821711925` is the de-identified view ([C4](../REQUIREMENTS.md)). It is built by dropping **all** identifiers HIPAA Safe-Harbor style: `pseudo_id` is a keyed HMAC, age band replaces DOB, state replaces address (details in [tokenization.md](tokenization.md)).

Because nothing in it is re-identifiable, it does **not** carry the `aws:sourceVpce` condition. It is readable **anywhere in the org**, but is still:

- **org-locked** (org `o-ncxqr8pp2c` only), and
- **TLS-only**.

This is the whole point of producing a second bucket: analytics and downstream consumers get org-wide reach without ever touching the network-pinned sensitive store.

---

## The four paths to the sensitive bucket

All four are deployed and verified working (except the noted P1 design pivot). Each path is a different consumer shape — a serverless reader, an on-prem batch job, a human web app, and a plain S3 role — chosen so the bucket policy is exercised from every realistic angle.

### P1 — Lambda redactor (with the OLAP-gating pivot)

A serverless "basic reader" that returns only non-sensitive fields. It reads **through a standard S3 Access Point**, strips every identifier, and returns just `gender` / `state` / `conditions`.

**Ordered hops:**

1. Caller invokes the **IAM-auth Lambda Function URL**
   `https://rrenoavoa5lhynclip4yomk4di0mozdx.lambda-url.ap-southeast-1.on.aws/`.
2. Function `ith-redactor` runs and reads the object **via the S3 Access Point** `...:accesspoint/ith-sensitive-ap`.
3. The bucket policy admits the request on the **same-account access-point** branch (`s3:DataAccessPointAccount = 118821711925`).
4. The function **strips every identifier** and returns redacted JSON.

**Verified:** returns redacted JSON (`gender` / `state` / `conditions` only).

> **The pivot to document:** the intended design was an **S3 Object Lambda Access Point** (transform on read). AWS gates S3 Object Lambda to "existing customers," so a brand-new account gets `AccessDenied` on create. We used the **supported equivalent** — **Lambda + standard Access Point + Function URL** — which delivers the same outcome (redaction on read) through the access-point branch of the bucket policy.

### P2 — On-prem Kubernetes over peering

A simulated on-prem batch consumer: a single-node **k3s** cluster on EC2 in the on-prem VPC, pulling sensitive data **across VPC peering**.

**Ordered hops:**

1. A k8s **CronJob** (image `public.ecr.aws/aws-cli/aws-cli`) runs on node `i-0a3dfcb0b4d3e50de` in the on-prem VPC (`192.168.0.0/16`).
2. Pod reaches **IMDS** for credentials (node `hop_limit = 2` so pods can reach it) and assumes the **node instance role** `ith-onprem-k8s-role`.
3. Request crosses the **VPC peering** into the workload VPC and hits the S3 **interface** endpoint `vpce-000ca0be99fa5595c`.
4. The bucket policy admits it on the `aws:sourceVpce = vpce-000ca0be99fa5595c` branch.

The node is **SSM-managed (no SSH)**. The on-prem VPC has an IGW for datacenter egress.

> **Gateway vs interface endpoint — the reason:** S3 **gateway** endpoints are route-table entries and are **not reachable across VPC peering**. So the peered on-prem path **must** use an S3 **interface** endpoint. Its private DNS is disabled, so its DNS name is a wildcard `*.vpce-...`; strip the leading `*.` to use it as the endpoint URL. (More in [network.md](network.md).)

> **Peering scalability caveat:** VPC peering is **non-transitive and N²** — every new VPC needing the data tier adds a peering plus route entries on **both** sides. It does not scale past a handful of VPCs. The scalable successor is **Transit Gateway** (or **PrivateLink** to a single endpoint service). Peering was used deliberately to match the brief and make the tradeoff concrete.

### P3 — EC2 web app — the only human path (C1)

The **sole human read path** ([C1](../REQUIREMENTS.md)). Humans cannot reach the bucket directly (no `vpce` ⇒ DENY), so all three admins read records here.

**Ordered hops:**

1. Admin starts an **SSM Session Manager port-forward** to instance `i-004a73751e979b264` (in the workload **private** subnet) — there is **no key pair, no SSH, no public IP**.
2. The web app (a **pure-Python-stdlib** app on `:8080`, hand-rolled SigV4 — no pip/boto3 so it runs on the no-internet host) uses the instance role `ith-ec2-webapp-role`.
3. App reads the sensitive bucket via the S3 **gateway** endpoint `vpce-0d4239508db2903d7`.
4. The bucket policy admits it on the `aws:sourceVpce = vpce-0d4239508db2903d7` branch.

**Why it's the only human path:** the bucket policy denies any read without an approved `vpce`, and a laptop has none. The EC2 app lives *inside* the VPC, so it is the one place a human's request acquires an approved `aws:sourceVpce`.

**Verified:** systemd active, `/healthz` ok, renders all 7 records — with identifiers **still tokenized** (even the human path never shows raw PHI; reversal is a separate [detokenize](tokenization.md) operation).

### P4 — the "s3" user — VPC-gated

The plain S3-reader identity, proving the gate works for a generic principal. `ith-s3-reader-role` (and the `ITH-S3Reader` permission set) **can** `s3:GetObject`, but the bucket policy still requires an approved `aws:sourceVpce`.

**Ordered hops:**

1. Principal assumes `ith-s3-reader-role` / uses the `ITH-S3Reader` permission set.
2. Calls `s3:GetObject` on the sensitive bucket.
3. The bucket policy checks `aws:sourceVpce`:
   - **From a laptop (no vpce):** `AccessDenied` (**verified**).
   - **From inside the VPC:** succeeds (**verified**).

The IAM allow is necessary but **not sufficient** — the network condition is the deciding factor. (`ITH-S3Reader` itself is scoped to `aws:sourceVpce = vpce-0d4239508db2903d7`; see [identity.md](identity.md).)

---

## Path comparison

| | **P1 Lambda redactor** | **P2 on-prem k8s** | **P3 EC2 web app (C1)** | **P4 "s3" user** |
|---|---|---|---|---|
| **Consumer** | Serverless function | k3s CronJob (batch) | Human via web UI | Generic S3 role |
| **Entry point** | IAM-auth Function URL | k8s CronJob → IMDS | SSM port-forward → `:8080` | AssumeRole + `GetObject` |
| **Identity** | `ith-redactor` exec role | `ith-onprem-k8s-role` | `ith-ec2-webapp-role` | `ith-s3-reader-role` |
| **Network onto bucket** | S3 **Access Point** | S3 **interface** endpoint (`vpce-000c…`) | S3 **gateway** endpoint (`vpce-0d42…`) | Whatever VPC the caller is in |
| **Bucket-policy branch** | `s3:DataAccessPointAccount` | `aws:sourceVpce` (interface) | `aws:sourceVpce` (gateway) | `aws:sourceVpce` (must match) |
| **What it returns** | Redacted (`gender`/`state`/`conditions`) | Full tokenized objects | All 7 records, **tokenized** | Full tokenized object |
| **Human?** | No | No | **Yes (the only one)** | No (denied from laptop) |
| **Status** | Verified (Object-Lambda pivot) | Verified | Verified | Verified (deny + allow) |

---

## Why this shape

- **Defense in depth:** field-level [vaultless tokenization (R18)](tokenization.md) sits under **per-patient SSE-KMS (R15)** on each object — so even a successful read returns tokens, and at-rest crypto blast-radius is one patient per key.
- **Network as the primary gate:** the bucket trusts the *path*, not just the *principal*. Three of four paths must present an approved `aws:sourceVpce`; the fourth uses an access point. This is what makes "no `vpce` ⇒ no PHI" hold for humans.
- **Two buckets, two reach models:** raw data is VPC-locked; de-identified data is org-wide. Consumers that don't need re-identifiable data never touch the sensitive store.

See [REQUIREMENTS.md](../REQUIREMENTS.md) for the full R1–R19 / C1–C4 mapping.

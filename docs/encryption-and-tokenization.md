# Encryption & Tokenization — per-patient KMS + vaultless tokens

> **In one line:** every patient record is first **field-tokenized** (deterministic,
> reversible, vaultless AES-SIV) and then encrypted **at rest under that patient's own
> KMS key** — two independent layers, so a record is protected even if one layer is
> bypassed. This page explains the per-patient CMK design and its cost-vs-compliance
> tradeoff (R15), vaultless tokenization in depth (R18), and the de-identified
> Safe-Harbor view.

**Requirements covered:** [R15](../REQUIREMENTS.md) (per-patient CMK / KMS),
[R18](../REQUIREMENTS.md) (vaultless tokenization), [R14](../REQUIREMENTS.md) (≥5
Synthea patients), [C4](../REQUIREMENTS.md) (de-identified second bucket).

**Related docs:** [design.md](design.md) · [data-plane-paths.md](data-plane-paths.md) ·
[detection-and-response.md](detection-and-response.md) ·
[tradeoffs-and-out-of-scope.md](tradeoffs-and-out-of-scope.md)

---

## 1. The layered model (read this first)

Two distinct controls protect each object, applied in this order:

| Order | Layer | What it protects against | Where it lives |
|---|---|---|---|
| **1st** | **Field tokenization** (vaultless AES-SIV) | Identifiers being readable *inside* the JSON, even to someone who can read the object | `app/tokenizer/tokenize.py`, run before upload |
| **2nd** | **Per-patient SSE-KMS at rest** | The object bytes being readable in S3 without `kms:Decrypt` on that patient's key | S3 default encryption + per-object CMK |

The order matters. By the time a value reaches S3 it is **already a token**, so the
KMS layer is encrypting tokens, not raw PHI. An attacker would need to defeat **both**
layers — get `kms:Decrypt` on the right patient key *and* hold the tokenization epoch
key — to recover a single SSN. This is defense in depth, not redundancy.

```
  raw value  ──tokenize()──►  tok:v1:…  ──SSE-KMS(per-patient CMK)──►  S3 object at rest
  (PHI)        (layer 1)      (token)      (layer 2)                    (encrypted token)
```

Even the **human read path never undoes layer 1**: the EC2 web app
([P3](data-plane-paths.md)) renders all 7 records with identifiers **still tokenized**.
Detokenization is a deliberate, separate step — the running UI does not do it.

---

## 2. Per-patient KMS (R15)

### 2.1 What we built

The literal brief was *"KMS, per person."* We implemented exactly that: **one
customer-managed CMK per patient** (7 patients → 7 keys).

| Property | Value |
|---|---|
| Key per patient | `alias/ith/patient/<12-hex>` — the 12-hex id is `sha256(patient_id)[:12]` |
| Rotation | Enabled (annual automatic) |
| Deletion window | 7 days |
| Key policy | account root `kms:*`, **plus** the 4 reader roles get `Decrypt` / `GenerateDataKey*` / `DescribeKey` |
| Used on | Each object in `phi-sensitive-118821711925` is encrypted under **its patient's** CMK |

Two more CMKs round out the design:

| Alias | Purpose |
|---|---|
| `alias/ith/deident` | Encrypts the de-identified bucket `phi-deident-118821711925` ([C4](data-plane-paths.md)) |
| `alias/ith/logs` | Encrypts CloudTrail, the CloudWatch Logs group, and the SNS topic ([detection-and-response.md](detection-and-response.md)) |

> **Note on access control vs. encryption.** Holding `kms:Decrypt` is necessary but not
> sufficient to read the sensitive bucket — the bucket policy still gates on
> `aws:sourceVpce`. The `ITH-Admin` permission set carries an **explicit `Deny kms:*`**,
> so the scoped admin can never decrypt anything. See
> [identity-and-mfa.md](identity-and-mfa.md).

### 2.2 The cost-vs-compliance tradeoff

This is the design decision the brief asks us to surface, so we state it plainly.

| | Per-patient CMK (what we built) |
|---|---|
| **Compliance upside** | **Per-subject crypto blast radius** — disable one key and *exactly one* patient's data goes dark, nobody else's. That is a clean per-subject "right to erasure" / incident lever. **Per-key CloudTrail** = a per-patient access audit trail for free. |
| **Cost / ops downside** | ~**$1 per key per month** plus API charges. AWS soft limit is ~**100k CMKs per region**, so this design does not scale to large populations. **Key sprawl**: lifecycle, rotation, and policy management multiply by patient count. |

### 2.3 Recommended production alternative

For a real system, prefer **one CMK + per-patient data keys** (envelope encryption),
distinguishing patients with **KMS encryption context** rather than separate keys.

| Goal | Per-patient CMK | One CMK + per-patient data keys / encryption context |
|---|---|---|
| Per-patient audit in CloudTrail | ✅ (per key) | ✅ (encryption context appears in the `kms:Decrypt` event) |
| Per-patient isolation | ✅ (disable the key) | ✅ (deny by encryption context / re-wrap the patient's data key) |
| Key sprawl | ❌ grows with patients | ✅ one key |
| Cost at scale | ❌ $1 × patients / month | ✅ one key |

Same audit and isolation story, **no sprawl**. We implemented the literal
per-patient-CMK as asked and document this as the path we would take in production.
(See also [tradeoffs-and-out-of-scope.md](tradeoffs-and-out-of-scope.md).)

---

## 3. Vaultless tokenization (R18)

### 3.1 Why vaultless

A classic token vault stores token↔value rows. That table becomes a **high-value
target**, a **scaling bottleneck**, and a **single point of failure**. We avoid it
entirely: every token is derived **cryptographically** from the value + a key, so there
is **no lookup table** to run, secure, or scale.

The tokenizer is `app/tokenizer/tokenize.py`. The fields it tokenizes are: **name,
SSN, MRN, phone, email, address line, postal code, and birth date.**

### 3.2 The token

```
tok:v{epoch}:{base64url( AES-SIV(value, AAD = fieldname) )}
```

| Property | How it is achieved | Why it matters |
|---|---|---|
| **Deterministic** | AES-256-**SIV** is deterministic: same `value` + same `field` → same token | Enables **equality joins** across records without revealing the value |
| **Reversible** | `detokenize()` decrypts with the epoch key | No vault needed to recover the original — the ciphertext *is* the token body |
| **Authenticated** | AES-SIV is an AEAD (SIV mode) | Tampered tokens fail to decrypt |
| **Domain-separated** | The **field name is the AAD** (Additional Authenticated Data) | The same value in two fields produces **different** tokens, and a token cannot be replayed into the wrong field |
| **Self-describing** | The `v{epoch}` prefix carries the key epoch | Detokenize knows which key to use — enables clean rotation (§3.4) |

### 3.3 Demo vs. prod key sourcing

The epoch DEK (data encryption key) is the secret that tokens are derived from. Where
it comes from differs by environment:

| | Demo (this repo) | Production |
|---|---|---|
| Epoch DEK source | `HKDF` from a fixed, **non-secret** test master baked into the script | `kms:GenerateDataKey` — the wrapped DEK is stored beside the epoch id; the plaintext DEK lives **only in memory** |
| Why | Script is self-contained and runs **offline** (no AWS calls to tokenize) | Real key custody; the DEK is never persisted in the clear |

> The demo master (`ITH-DEMO-MASTER-KEY-NOT-FOR-PRODUCTION-USE-ONLY`) is intentionally
> non-secret — it exists so a reviewer can run the tokenizer and prove the round-trip
> without any AWS credentials. **It is not the production design.**

### 3.4 Rotate-forward without mass re-tokenization

Because every token carries its epoch, key rotation is cheap:

1. **Mint a new epoch** — generate a new DEK, mark it current. *New writes* use it.
2. **Keep old-epoch DEKs** — only to **decrypt** old tokens. Old data is never touched.
3. **Retire lazily** — as old data ages out, drop the old epoch's DEK.

There is **no mass re-tokenization** event — no need to rewrite every object to rotate
keys. Reads transparently route to the correct key via the token's `v{epoch}` tag;
writes always use the current epoch.

```
  epoch 1 ─────────────► (retained for reads only) ─────► retired when data ages out
                  ▲
  rotate ─────────┘
  epoch 2 ─────────────► current: all NEW writes use this DEK
```

### 3.5 The tradeoff to be honest about

Deterministic tokens (within an epoch) are what make joins possible — and that
**determinism is a re-identification surface** compared with fully random vault tokens.
It is acceptable for de-identified analytics and is the explicit price of the vaultless,
join-able design. The field-name AAD limits cross-field correlation, and the
Safe-Harbor view (§4) removes determinism entirely for the org-wide copy.

---

## 4. The de-identified Safe-Harbor view (C4)

The sensitive view tokenizes identifiers but **keeps them present** (reversibly). The
de-identified view **drops all direct identifiers** in the HIPAA **Safe-Harbor** style.
This is the copy that lands in the org-wide bucket `phi-deident-118821711925` and is
also what the redactor Lambda ([P1](data-plane-paths.md)) returns.

| Sensitive view (`phi-sensitive`) | De-identified view (`phi-deident`) |
|---|---|
| `name`, `ssn`, `mrn`, `phone`, `email`, address, postal, birth date — **tokenized but present** | **None of these exist** |
| `patient_id` | `pseudo_id` = keyed **HMAC** of the patient id (non-reversible) |
| `birth_date` (tokenized) | `age_band` only (e.g. `40-49`); ages **> 89 aggregated to `90+`** per Safe Harbor |
| `address_line` + `postal` (tokenized) | `state` only — no street, no ZIP |
| `gender`, `city`, `conditions` | `gender`, `state`, `conditions` |

Key differences from the sensitive view:

- **`pseudo_id` is one-way.** It is a keyed HMAC, not a reversible token — there is no
  detokenize path back to the patient id.
- **No date precision.** Date of birth becomes a 10-year age band, with the Safe-Harbor
  rule that anyone over 89 collapses into a single `90+` bucket.
- **Geography is coarsened.** Street and postal code are gone; only state remains.

Because it contains no identifiers, this view is safe to read **anywhere in the org**
(no `aws:sourceVpce` gate) — it is still org-locked (RCP) and TLS-only. The VPC-only
sensitive bucket and the org-wide de-identified bucket together make the
VPC-condition delta concrete. See [data-plane-paths.md](data-plane-paths.md).

---

## 5. How it ties together end to end

1. **Generate** — `app/tokenizer/tokenize.py` reads the Synthea FHIR bundles
   ([R14](../REQUIREMENTS.md), 7 patients) and writes two JSON views per patient plus a
   `patient-index.json`.
2. **Index drives KMS** — Terraform reads `patient-index.json` and creates **one CMK per
   patient** using the `12-hex` key id (§2.1).
3. **Upload, layered** — the sensitive view (tokens) is uploaded under its patient's CMK
   (layer 1 then layer 2); the de-identified view is uploaded under `alias/ith/deident`.
4. **Read** — humans read via the EC2 web app with identifiers **still tokenized**
   ([P3](data-plane-paths.md)); automation gets the Safe-Harbor view via the redactor
   ([P1](data-plane-paths.md)); the in-VPC `s3` principal can fetch the raw (tokenized)
   object ([P4](data-plane-paths.md)).
5. **Rotate** — minting a new token epoch (§3.4) and rotating CMKs (§2.1) are both
   incremental; neither requires rewriting all objects.

---

## 6. Quick reference

| Question | Answer |
|---|---|
| How many KMS keys? | 7 per-patient CMKs + `deident` + `logs` |
| Token format | `tok:v{epoch}:{base64url(AES-SIV(value, AAD=field))}` |
| Is tokenization reversible? | Yes — `detokenize()`, vaultless (no lookup table) |
| What makes joins work? | AES-SIV is deterministic per (value, field, epoch) |
| How do we rotate token keys? | Mint a new epoch for new writes; keep old DEKs for reads; no mass re-tokenization |
| What's in the de-identified copy? | `pseudo_id` (HMAC), `gender`, `age_band`, `state`, `conditions` — no identifiers |
| Recommended prod KMS design | One CMK + per-patient data keys / encryption context |

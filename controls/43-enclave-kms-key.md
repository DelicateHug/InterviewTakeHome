# [43] Attestation-gated enclave KMS key

**Type:** Customer-managed KMS CMK (`alias/ith/enclave`) with a Nitro-attestation condition

> **In plain terms —** A key that unlocks *only* for one specific, measured program running inside a sealed enclave on the on-prem node — not the node's OS, not its IAM role, not even the account root. The key checks the enclave's cryptographic fingerprint (PCR0) on every call. It is the strongest control in the system: even a fully compromised host cannot decrypt the data.

## Controls applied

- **Prevention:** The key policy carries an explicit **Deny** on `kms:Decrypt` + `kms:GenerateDataKey*` unless the request presents a Nitro **attestation document whose PCR0 equals the measured enclave image** (`kms:RecipientAttestation:PCR0`). An explicit deny overrides every allow, so it beats the root-account delegation *and* the node role's IAM grant — without the enclave, the key is unusable. `...IfExists` makes a request with **no** attestation (any normal caller, including the node role itself or root) match the deny too. Used **only** for client-side envelope encryption performed inside the enclave [[44]](44-nitro-enclave.md); it is deliberately **never** an S3 SSE key (S3's own `GenerateDataKey` carries no attestation and would be denied). PCR0 is captured on the node and locked in by a two-phase apply (`scripts/deploy-enclave.ps1`). PCR0-only by choice — see [OutOfScopeNotes](OutOfScopeNotes.md) for instance-binding (PCR4).
- **Detection:** Org CloudTrail [[33]](33-cloudtrail.md) records every `Decrypt`/`GenerateDataKey` on this key — both the attested successes (principal = node role, from the enclave) and every denied non-attested attempt — plus any `kms:PutKeyPolicy` that would lift the gate.
- **Alert:**
  - A non-enclave call → AccessDenied → unauthorized-api alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md)
  - a key-policy edit → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).

## What would trigger an alert

- Any `GenerateDataKey`/`Decrypt` on `alias/ith/enclave` **without** a matching PCR0 attestation (the node OS/role, root, a stolen credential) → **explicit-deny AccessDenied** → unauthorized-api alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md).
- Someone editing the key policy to drop the PCR0 Deny (lifting the gate) → org-level change captured by CloudTrail → change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).

---
[< controls index](README.md) | [< home](../README.md)

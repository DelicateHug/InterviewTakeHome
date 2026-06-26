# [44] Attested Nitro Enclave + read/write pod (P5)

**Type:** AWS Nitro Enclave on the on-prem k8s node + a k8s Job that reads/writes S3

> **In plain terms —** The on-prem Kubernetes node now runs a sealed micro-VM (a Nitro Enclave) with no network and no disk. A normal pod reads *and writes* the sensitive bucket, but it only ever touches ciphertext — every encrypt/decrypt is delegated to the enclave, which is the only thing the data key [[43]](43-enclave-kms-key.md) will unlock for. So the data is protected by hardware attestation, not just network position.

## Controls applied

- **Prevention:**
  - The enclave runs in **production mode** (real PCR measurement, no `--debug-mode`), on an enclave-capable `c6i.xlarge`; the node is **SSM-only** (no SSH, no key pair).
  - The pod (`phi-rw-enclave`, hostNetwork) handles **only ciphertext**: it calls a host **broker** that bridges to the enclave over **vsock**; the enclave reaches KMS through a host **vsock-proxy** and performs **AES-256-GCM inside** the enclave, so the plaintext data key never leaves it.
  - The node role can `PutObject` **only** under `enclave/*`, and those puts carry **SSE-KMS** to satisfy the org S3 SCP [[07]](07-scp.md) — defence-in-depth at rest on top of the client-side envelope.
  - Read/write still crosses the VPC peering via the S3 interface endpoint, so the bucket's `aws:sourceVpce` gate [[20]](20-s3-sensitive.md) holds. The data key is obtainable **only** inside the measured enclave [[43]](43-enclave-kms-key.md).
- **Detection:**
  - Org CloudTrail [[33]](33-cloudtrail.md) logs the enclave's KMS calls and any direct (non-attested) attempt
  - GuardDuty [[37]](37-guardduty.md) watches the account
  - object writes land under `enclave/` with SSE-KMS.
- **Alert:** A KMS call from the node **without** attestation → unauthorized-api alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md); tampering that changes the enclave image changes PCR0, so [[43]](43-enclave-kms-key.md) denies it until the key is re-locked (the failures surface via the alarms).

## What would trigger an alert

- The node OS / instance role / a stolen credential trying to decrypt patient data directly (no enclave) → **AccessDenied** at [[43]](43-enclave-kms-key.md) → unauthorized-api alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md).
- Swapping or tampering with the enclave image (PCR0 changes) → KMS [[43]](43-enclave-kms-key.md) refuses the new measurement until it is re-locked via the two-phase deploy — a controlled, auditable change rather than a silent one.

---
[< controls index](README.md) | [< home](../README.md)

# Deployment Evidence

Captured from the **live deployment** to isolated account `118821711925` in region
`ap-southeast-1`. Everything below was produced by the Terraform in this repo and
verified with real calls — not mock-ups.

## Org / guardrails (00-org)

| Item | Value |
|---|---|
| Org | `o-ncxqr8pp2c` (root `r-33e3`, SCP + RCP both enabled) |
| Management account | `337066574719` |
| New OU | `InterviewTakeHome` = `ou-33e3-5p8xygxw` |
| New member account | `ith-workload` = **`118821711925`** |
| SCP (S3 guardrails) | `p-kt4wutiz` — attached to the OU only |
| RCP (deny S3 outside org) | `p-02p8l548gj` — attached to the OU only |

`list-policies-for-target` on the OU returns `ith-scp-s3-guardrails` and
`ith-rcp-s3-org-only` (plus the AWS-managed FullAccess defaults).

## Identity (10-identity)

- AWS access portal: **https://d-96677e53fe.awsapps.com/start/**
- 3 permission sets created: `ITH-SuperAdmin` (`ps-5d0bf2b3199ca111`), `ITH-Admin`
  (`ps-e43309226b317833`, denies `kms:*`), `ITH-S3Reader` (`ps-50b047f6d2e54fbe`,
  VPC-only). `entra_enabled = false` (Entra/CA written but not applied — guardrail).
- **[42] Permissions boundary on `ITH-SuperAdmin`** (customer-managed policy
  `ITH-SuperAdmin-Boundary` in the member account; `NotAction kms:*` ceiling, no Deny).
  Caps SuperAdmin's MAX to all-except-KMS by intersection, so `aws kms list-aliases` as
  SuperAdmin returns `AccessDenied` — distinct from `ITH-Admin`'s explicit `Deny kms:*`.

## KMS + data (R14/R15/R18)

- **7 per-patient CMKs** (`alias/ith/patient/*`), `alias/ith/deident`, `alias/ith/logs`.
- 7 patients uploaded to **both** buckets; each sensitive object encrypted under its
  own patient CMK. Proof from an actual `get-object` (P2 below):
  `SSEKMSKeyId = arn:aws:kms:ap-southeast-1:118821711925:key/594d5f0a-…` (a per-patient key).
- Vaultless tokenization round-trip proven by `app/tokenizer/tokenize.py`:
  `ssn` token `tok:v1:…` detokenizes back to `999-34-3195`.

## The five paths (all verified)

| Path | Test | Result |
|---|---|---|
| **P1** Lambda redactor | `lambda invoke ith-redactor {key: patients/088047ea….json}` | `200` + JSON containing **only** `gender/state/conditions/_redacted_by` — no identifiers. ✅ |
| **P2** on-prem k8s | k3s pod `aws s3api get-object … --endpoint-url https://bucket.vpce-000ca0be9….vpce.amazonaws.com` (across peering) | `READ_OK … via interface-vpce across peering`; response shows `SSEKMSKeyId` = per-patient CMK. ✅ |
| **P3** EC2 web app | `curl http://localhost:8080/` over SSM port-forward on `i-004a73751e979b264` | `systemctl=active`, `/healthz=ok`, renders all 7 records **tokenized**, *and* a second table that **detokenizes** them (AES-SIV epoch key) to prove the path can reverse when authorised. ✅ |
| **P4** `s3` user | assume `ith-s3-reader-role` from a laptop (no VPC) then `get-object` | `AccessDenied … explicit deny in a resource-based policy` (the VPC gate). In-VPC the same call works (= P3 mechanism). ✅ |
| **P5** attested enclave R/W | `kubectl logs job/phi-rw-enclave` on the Nitro-enabled node `i-0303f39bf8f751014` | pod `WROTE … enclave/<id>.enc` then `READ_OK {…}` with `ROUNDTRIP_MATCH=yes` — encrypt+decrypt done **inside the enclave**; the node role calling KMS **without** attestation is **denied**. ✅ |

### C1 — humans can't read directly (must use the EC2 UI)
From the management/laptop context, `s3api head-object` / `list-objects` on
`phi-sensitive-118821711925` returns **`AccessDenied … explicit deny`** — direct human
reads are blocked; the only human read path is the in-VPC EC2 web app.

### P5 — attested Nitro Enclave read/write (the strongest control)

Node `i-0303f39bf8f751014` (`c6i.xlarge`, `enclave_options` on) runs a Nitro Enclave; the
key `alias/ith/enclave` (`…/key/aaaccd84…`) denies `Decrypt`/`GenerateDataKey` unless the
caller presents a Nitro attestation whose **PCR0** matches the measured image.

- **Enclave measured & running:** `nitro-cli describe-enclaves` →
  `State RUNNING, CID 16`, `PCR0 = f5ec5cdfcd6242a0e278fe3a6c5681ebd8719aa90a02e6ad5e844812d42219e419ee5dd0d83fa28edb4c75ddf9c4d0e1`.
  The same value is locked into the key policy (Terraform `enclave_pcr0`) and published to
  SSM `/ith/enclave/pcr0`.
- **Round-trip (positive):** `kubectl logs job/phi-rw-enclave` →
  `encrypt -> {"ok": true, …}` · `WROTE s3://phi-sensitive-118821711925/enclave/2a013c39….enc`
  · `READ_OK {"patient_id":"2a013c39…","ssn":"999-00-1234","name":"Enclave Demo","note":"written via attested Nitro Enclave (PCR0-gated KMS)"}`
  · **`ROUNDTRIP_MATCH=yes`** (`phase=Succeeded`). Encrypt and decrypt both happen **inside**
  the enclave (AES-256-GCM); the pod only ever holds ciphertext.
- **Negative test (the proof):** the *same* node role, calling KMS directly with **no
  attestation** →
  `aws kms generate-data-key --key-id alias/ith/enclave --key-spec AES_256` →
  **`AccessDeniedException … explicit deny in a resource-based policy`**. So neither the node
  OS, nor its IAM role, nor root can unwrap the data — only the measured enclave.
- **At rest:** the stored object `enclave/2a013c39….enc` is **562 bytes of opaque
  ciphertext**, `ServerSideEncryption = aws:kms` under a **different** key
  (`…/key/b43be968…`, the bucket default — *not* the enclave key, which by design can't be an
  SSE key). Client-side envelope + SSE-KMS at rest = defence in depth.

> PCR0-only by choice; `controls/OutOfScopeNotes.md` explains how prod would also bind the
> instance (PCR4) and scope the key's workloads to specific hosts.

## Detection / response (R4/R11/R12)

| Control | Evidence |
|---|---|
| CloudTrail | `get-trail-status ith-trail` → `IsLogging = True` (multi-region, log-file validation, KMS, S3 data events) |
| GuardDuty | detector `Status = ENABLED` |
| Alarms (9) | `describe-alarms` shows all 9; **3 already in `ALARM`** from real activity: `ith-s3-access-denied`, `ith-s3-policy-change`, `ith-unauthorized-api` |
| R12 role-credential alerting (GuardDuty) | Satisfied by GuardDuty, not a custom Lambda. The detector is `ENABLED` (row above) and the sev≥4 EventBridge rule routes findings to SNS. The two relevant findings are `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS` (EC2 role creds used from an IP outside AWS) and `.InsideAWS` (used from another AWS account). Exercise the path on demand with `aws guardduty create-sample-findings --detector-id <id> --finding-types UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS` → finding fires → EventBridge → SNS email. |
| SNS | topic `ith-security-alerts` (KMS-encrypted); email `dylanheathsmart@gmail.com` is **`PendingConfirmation`** — click the confirmation email to receive alerts |

## How to reproduce the checks

```bash
# P1
aws lambda invoke --function-name ith-redactor \
  --payload '{"queryStringParameters":{"key":"patients/088047ea-5cf6-2dfd-3b89-c0c8a1813de8.json"}}' \
  --cli-binary-format raw-in-base64-out --profile ith-workload --region ap-southeast-1 out.json && cat out.json

# P3 (then browse http://localhost:8080)
aws ssm start-session --target i-004a73751e979b264 --profile ith-workload --region ap-southeast-1 \
  --document-name AWS-StartPortForwardingSession --parameters portNumber=8080,localPortNumber=8080

# P4 (expect AccessDenied)
creds=$(aws sts assume-role --role-arn arn:aws:iam::118821711925:role/ith-s3-reader-role \
  --role-session-name t --profile ith-workload) # export & aws s3api get-object ... -> denied

# detection
aws cloudtrail get-trail-status --name ith-trail --query IsLogging --profile ith-workload --region ap-southeast-1
aws cloudwatch describe-alarms --alarm-name-prefix ith- --query "MetricAlarms[].[AlarmName,StateValue]" --output text --profile ith-workload --region ap-southeast-1
```

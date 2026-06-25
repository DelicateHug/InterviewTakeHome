# Out-of-scope notes & recommendations

Things deliberately not built (or not enforced), with the reason and the recommended
production action. Listed so the interviewer sees they were considered, not missed.

## Data — Synthea

- All patient data is **synthetic**, generated with **Synthea** (7 patients) — contains
  **no real PHI**, so it is safe to commit to a public repo.
- Sensitive fields are **vaultless-tokenized** before upload; a de-identified (Safe-Harbor)
  copy is produced too. See [25] tokenizer.
- Prod would generate/ingest real ePHI under a signed **AWS BAA**; only HIPAA-eligible
  services would be in scope.

## Hardware / phishing-resistant MFA — NOT enforced (should be)

- The phishing-resistant-MFA **Conditional Access** policy [04] is written as IaC but
  **left disabled** (`enable_entra_changes=false`) to avoid changing the live tenant.
- **Recommendation:** enforce it. Auth strength `...0004` ("Phishing-resistant MFA")
  requires FIDO2 security keys / passkeys / Windows Hello / CBA — i.e. **hardware-backed**
  factors — and, because it is the only accepted grant, **blocks non-MFA / weak MFA**.
- Example Microsoft Graph API call to create the policy:

```http
POST https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies
Authorization: Bearer <token>
Content-Type: application/json
```
```json
{
  "displayName": "Require phishing-resistant MFA for AWS admins",
  "state": "enabled",
  "conditions": {
    "clientAppTypes": ["all"],
    "applications": { "includeApplications": ["<AWS-IdC-enterprise-app-id>"] },
    "users": { "includeGroups": ["<interview-admins-group-id>"] }
  },
  "grantControls": {
    "operator": "OR",
    "authenticationStrength": { "id": "00000000-0000-0000-0000-000000000004" }
  }
}
```
- `00000000-0000-0000-0000-000000000004` is the built-in **Phishing-resistant MFA**
  authentication strength. (Terraform equivalent is in `terraform/10-identity/entra.tf`.)

## Centralize root access for member accounts — recommended

- The new member account [09] still has its own **root user credentials**. AWS now lets you
  **remove member-account root credentials** and perform the few root-only actions centrally
  from the management / delegated admin account (**IAM > Centralize root access**).
- **Recommendation:** enable centralized root access and delete the member-account root
  credentials — removes a standing high-value credential and a long-lived attack surface.
- Pairs with: root-usage alerting (below) and SCP `DenyRootUser` guardrails.

## Other AWS services considered (out of scope here)

| Service | Why out of scope | What it would add |
|---|---|---|
| AWS Control Tower | overkill for 1-OU/1-account | automated landing zone + guardrails |
| AWS Backup | orthogonal to access control | immutable, cross-region, tested restores |
| ALB | no public web tier (SSM-only) | managed L7 ingress + WAF attach point |
| Application Recovery Controller | no HA region here | multi-region failover routing |
| Root-account usage alerting | root lives in mgmt acct we don't fully own | CloudWatch alarm on any root use |
| Centralized logging (Log Archive acct) | kept logs in workload acct | tamper-evident org-wide log sink |
| Amazon Inspector | orthogonal | runtime/SCA vuln scanning of EC2 + libs |

## Tradeoffs (called out)

- **Per-patient KMS CMK [22]:** strong per-subject isolation + per-key audit, but ~$1/key/mo,
  ~100k keys/region soft limit, and key sprawl. **Prod alternative:** one CMK + per-patient
  data keys / encryption context (same isolation + audit, no sprawl).
- **VPC peering [12]:** non-transitive & N^2; **Transit Gateway** (or PrivateLink) is the
  scalable successor. Used here to match the brief.
- **VPC endpoints [13][14][15]:** operational overhead (extra resources, endpoint policies,
  silent public-endpoint fallback trap) but a strong control for sensitive data — keeps S3
  traffic on the AWS backbone and powers the `aws:sourceVpce` gate.
- **Vaultless tokens:** deterministic (enables equality joins) = a re-identification surface
  vs. random vault tokens — acceptable for de-identified analytics.

---
[< controls index](README.md) | [< home](../README.md)

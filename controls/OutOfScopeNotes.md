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

### Verifying the Conditional Access policy (once enabled)

CA [04] is doc-only, so there is nothing live to test yet; the **design is sound** —
making auth strength `...0004` the *only* accepted grant both requires phishing-resistant
MFA and blocks password-only / weak-MFA in one policy (R2 + R3). When enabled, verify it
three ways:

1. **Positive:** sign in to the AWS access portal with a FIDO2 key / passkey → succeeds.
   The Entra **sign-in log** row shows the satisfied **authentication strength** = `...0004`.
2. **Negative:** attempt a password-only / SMS sign-in as an admin → **blocked**; the
   sign-in log shows CA result `Failure` with this policy named as the reason.
3. **Coverage:** Entra → **Conditional Access → Policies → (policy) → "What If"** confirms
   it applies to the admin group on the AWS Identity Center enterprise app — and to no one
   else.

Drift: any toggle/edit of the policy writes an Entra **audit-log** entry; recommend Entra
Identity Protection / a SIEM alert on CA-policy changes — the Entra analogue of the AWS
change-alerter [40].

### Managed devices only — also recommended (doc-only)

The same CA [04] design would **also enforce managed devices only**: add a **device grant** —
*Require device to be marked as compliant* (Intune-managed) or *Require Microsoft Entra hybrid
joined device* — so AWS admin access is allowed **only from a managed/compliant endpoint** and
sign-ins from unmanaged or BYOD devices are **blocked even with a valid passkey**. Stacks with
the phishing-resistant-MFA grant above (you have *something you are/have* **and** a trusted
device); left disabled here under the same no-tenant-changes guardrail.

### SSM sessions from managed devices only — SCP belt to the CA brace (doc-only)

The human path to the EC2 web app [28] is **SSM-only** (Session Manager shell / port-forwarding
through the SSM interface endpoint [15] — e.g. `aws ssm start-session --document-name
AWS-StartPortForwardingSession`); there is no public tier. So "managed device only" for that path
is enforced **primarily by the CA [04] device grant above** — an unmanaged/BYOD endpoint never
obtains a federated session in the first place, and with no session there is nothing to call
`ssm:StartSession` with.

As **defense-in-depth inside AWS** (so a loosened or mis-scoped CA policy can't silently re-open
SSM), extend the org SCP [07]/[41] to **deny `ssm:StartSession` unless the federated session
carries a device-posture tag**. This re-checks posture at the API-authorization boundary,
independent of the IdP:

```json
{
  "Sid": "DenySSMSessionUnlessManagedDevice",
  "Effect": "Deny",
  "Action": ["ssm:StartSession", "ssm:ResumeSession"],
  "Resource": "*",
  "Condition": {
    "StringNotEquals": { "aws:PrincipalTag/DeviceTrust": "Managed" }
  }
}
```

- **Where the tag comes from.** Entra [01] CA marks the device *compliant*; that claim is mapped
  through **IAM Identity Center [02] ABAC** to a session tag `DeviceTrust=Managed`
  (`https://aws.amazon.com/SAML/Attributes/PrincipalTag:DeviceTrust`), which lands in the request
  context as `aws:PrincipalTag/DeviceTrust`. SCP can't see the device — it only tests this tag,
  so the **whole control hinges on the IdP being the authority for it.**
- **Fail-closed.** Use plain `StringNotEquals`, **not** `...IfExists`: a *missing* tag then makes
  the Deny fire (no posture proof → blocked). `IfExists` would skip the Deny when the tag is
  absent — fail-open, the opposite of what we want.
- **No self-tagging path.** Access is SSO-only via permission sets [03]; there is no
  `sts:AssumeRole`-with-`Tags` path for a caller to inject a forged `DeviceTrust=Managed`, and the
  account allow-list SCP [41] + SuperAdmin boundary [42] keep it that way. (If break-glass is
  needed, exempt one role via the same tag pattern rather than weakening the condition.)
- **Denied attempts alert.** A blocked `ssm:StartSession` writes `AccessDenied` to CloudTrail [33];
  extend the access-denied alarm pattern [35]/[40] → SNS [36] to page on it, the SSM analogue of
  the `s3-access-denied` alarm.

Left doc-only under the same no-tenant-changes guardrail as CA [04]: the SCP itself is additive to
[07]/[41] and wouldn't break the tenant, but it depends on the Entra→IdC device-posture attribute
mapping, which isn't wired in while the CA config is disabled.

## Root protection via AWS Organizations — out of scope here

The ITH root user [05] lives in the **management account we don't fully own**, so we don't
deploy root controls against it. Three production controls would close the gap; all are
additive and would not break the tenant:

- **Root-usage / root-login alert.** A CloudWatch alarm on any root sign-in or root API
  call. The member-account version already exists — the `root-usage` alarm [35] fires off
  CloudTrail. Production: extend the same metric filter to the **org / management trail** so
  the high-value management-account root is covered too.
- **Remove member-account root credentials (centralize root access).** AWS now lets you
  **delete a member account's root credentials** and perform the few root-only tasks
  centrally from the management / delegated-admin account (**IAM → Centralize root access**).
  This removes a standing, long-lived high-value credential from [09] entirely. Pairs with a
  `DenyRootUser` SCP guardrail.
- **Multi-party approval (MPA) for AWS Organizations.** A team-of-approvers gate: a sensitive
  operation requires sign-off from a separate **approval team** through an authentication path
  **independent of the account's own (or root) credentials**. Today it is integrated with
  **AWS Backup logically air-gapped vaults** — backup recovery/sharing can be authorized by
  the approval team *even if the owning account's root is compromised or the account is
  inaccessible*. Recommended alongside centralize-root-access so that **no single
  root/admin compromise can unilaterally destroy or exfiltrate the data's last protected
  copy**.

## Locking the sensitive bucket to the super admin only (tag + org condition)

Goal: only the **super admin** [03] may operate on or modify the sensitive bucket [20];
everyone else is denied — keyed on a **principal tag + `aws:PrincipalOrgID`** condition — and
every **denied attempt alerts**.

**Enforcement is a policy, not AWS Config — verified.** AWS Config is **detective only**: it
records configuration and evaluates rules *after* a change, and can auto-remediate via SSM
Automation — but it **cannot block an API call in real time**. To actually *prevent* `s3:*`
for everyone but the super admin you need a **preventive** control:

- **SCP [07]/[41]**, the **bucket policy [20]**, or the **RCP [08]** with an explicit
  `Deny s3:*` on the sensitive bucket, written so it does **not** apply when the principal is
  the super-admin role — e.g. condition on `aws:PrincipalTag/role = super-admin` **and**
  `aws:PrincipalOrgID = o-ncxqr8pp2c`, with that tagged principal as the *only* exception.
  This is the standard "deny-all-except-tagged-principal" guardrail and stacks on top of the
  existing VPC-lock [20].
- **AWS Config is complementary, not the enforcer.** A managed rule (e.g.
  `s3-bucket-policy-not-more-permissive`, `s3-bucket-public-read/write-prohibited`, BPA rules)
  **detects** drift if the bucket policy is ever loosened and can **auto-remediate** by
  re-applying the hardened policy — but the SCP/bucket policy is what stops the action.

**Failed attempts already alert.** Any denied `s3:*` (wrong tag, outside org, outside VPC)
writes `AccessDenied` to CloudTrail and trips the **`s3-access-denied`** alarm [35] → SNS [36].
If an attacker instead spins up a **new user/role** to obtain the tag, that `CreateUser` /
role change is itself caught by the **change / CreateUser alerter [40]** (super admin
excluded) → SNS [36].

## Behavior-based / risk-based sign-in — AWS + Entra

Anomaly-driven detection layered on top of the static rules, split by side:

- **AWS side — already built.** **GuardDuty [37]** flags anomalous credential/API behaviour
  (impossible-travel, Tor / anonymous-IP use, recon, atypical API calls) with no rules to
  write. It also satisfies R12: its `InstanceCredentialExfiltration.OutsideAWS` / `.InsideAWS`
  findings page when an EC2 role's credentials are used off the instance — from an IP outside
  AWS, or replayed from another AWS account. Routes to SNS [36]. (A bespoke "alert on
  `AssumeRole` from an IP outside an allow-list" Lambda was considered and removed as a
  duplicate of this managed coverage.)
- **Entra side — recommended (doc-only, like the rest of the Entra config).** Add a
  **risk-based Conditional Access** policy backed by **Entra ID Protection**: it scores each
  sign-in on behavioural signals (leaked credentials, anonymous IP, impossible travel,
  unfamiliar location/device) and can step-up to phishing-resistant MFA or **block on high
  sign-in / user risk**. Complements the static phishing-resistant-MFA CA [04]; left disabled
  here under the same no-tenant-changes guardrail.

## Other AWS services considered (out of scope here)

| Service | Why out of scope | What it would add |
|---|---|---|
| AWS Control Tower | overkill for 1-OU/1-account | automated landing zone + guardrails |
| AWS Config | **detective only** — can't *prevent* an action (records + auto-remediates after the fact) | config-drift detection, auto-remediation, conformance packs |
| Multi-party approval (Organizations) | not needed at this scale | team-approval gate for sensitive ops (e.g. air-gapped backup recovery) independent of account/root creds |
| AWS Backup | orthogonal to access control | immutable, cross-region, tested restores |
| ALB | no public web tier (SSM-only) | managed L7 ingress + WAF attach point |
| Application Recovery Controller | no HA region here | multi-region failover routing |
| Root-account usage alerting | root lives in mgmt acct we don't fully own (see *Root protection* above) | CloudWatch alarm on any root use |
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

# Identity &amp; Phishing-Resistant MFA

> **Summary:** Human sign-in flows through **Microsoft Entra → AWS IAM Identity Center** (SCIM-federated). Three users map to three least-privilege permission sets, and a **phishing-resistant MFA** Conditional Access policy is the *only* accepted way in. The Entra users, group, account assignments, and the CA policy are **written as Terraform but disabled by default** so nothing breaks on the live tenant — flip one variable to enable them in an isolated tenant.

**Login URL (AWS access portal):** [`https://d-96677e53fe.awsapps.com/start/`](https://d-96677e53fe.awsapps.com/start/)

Related docs: [S3 &amp; data paths](./s3-and-data-paths.md) · [KMS &amp; tokenization](./kms-and-tokenization.md) · [Network](./network.md) · [Detection &amp; response](./detection-and-response.md) · [Requirements](../REQUIREMENTS.md)

---

## 1. How sign-in works (Entra → Identity Center via SCIM)

```
Microsoft Entra (delicatehug.com)
        │  SCIM provisioning  (users carry scim.aws.com external ids)
        │  SAML sign-in
        ▼
AWS IAM Identity Center  (instance ssoins-46812a8af28769cf)
   identity store d-96677e53fe
        │  permission set → account assignment
        ▼
ith-workload account  (118821711925)
```

- **Identity Provider:** Microsoft Entra is the IdP. Users and groups are provisioned into Identity Center via **SCIM**, so each federated user carries a `scim.aws.com` external id.
- **AWS side:** the IAM Identity Center instance `ssoins-46812a8af28769cf` (identity store `d-96677e53fe`) holds the permission sets and account assignments.
- **Where users land:** all assignments target the **`ith-workload`** member account (`118821711925`) inside the isolated **`InterviewTakeHome`** OU.
- **Entry point:** users authenticate at the access portal — **[`https://d-96677e53fe.awsapps.com/start/`](https://d-96677e53fe.awsapps.com/start/)** — and choose a permission set to enter the account.

---

## 2. The three users and their permission sets

Three Entra users map one-to-one to three permission sets. All three permission sets are **created for real** in Identity Center; they stay **inert until assigned** (assignments are part of the disabled Entra block — see [§4](#4-no-breaking-changes-guardrail-written-but-disabled)).

| Entra user | Permission set | What it can do | Hard limits |
|---|---|---|---|
| `ith-superadmin@delicatehug.com` | **ITH-SuperAdmin** | AWS managed `AdministratorAccess` | Break-glass / full admin |
| `ith-admin@delicatehug.com` | **ITH-Admin** | Operate the workload: `s3`, `ec2`, `cloudwatch`, `logs`, `cloudtrail`, `guardduty`, `sns`, `ssm`, plus `iam:Get*`/`iam:List*` | **Explicit `Deny kms:*`** — cannot touch any key |
| `ith-s3@delicatehug.com` | **ITH-S3Reader** | `s3:GetObject` / `s3:ListBucket` on the **phi buckets only**, plus `kms:Decrypt` | Allowed **only when `aws:sourceVpce = vpce-0d4239508db2903d7`** (the workload VPC endpoint) |

### Why ITH-Admin has no KMS

The day-to-day admin can run the whole workload — instances, buckets, logging, alerting — but an **explicit `Deny kms:*`** means it can never read, disable, or delete a customer-managed key. Encryption/decryption authority is separated from operational authority, so an admin compromise does not become a plaintext-PHI compromise. (Decrypt rights live with the **reader roles** keyed into each per-patient CMK — see [KMS &amp; tokenization](./kms-and-tokenization.md).)

### Why ITH-S3Reader is VPC-only

ITH-S3Reader can read object bytes, but the **bucket policy denies** the read unless the request arrives through the workload S3 endpoint `vpce-0d4239508db2903d7`. This is **path P4** in the data-access design:

- Assuming the role **from a laptop (no `vpce`) → `AccessDenied`** (verified).
- The same call **from inside the VPC → succeeds** (verified).

So even a user whose *IAM* permissions allow `GetObject` cannot pull PHI from the open internet — they have to be on the private network path. See [S3 &amp; data paths](./s3-and-data-paths.md) for all four paths and the human web-app path (C1).

---

## 3. Phishing-resistant MFA via Conditional Access

The sign-in security control is an **Entra Conditional Access (CA) policy** scoped to the AWS app for the **`ITH-Interview-Admins`** group.

**Design:**

- **Grant control = authentication strength** set to the built-in **"Phishing-resistant MFA"** strength
  (`/policies/authenticationStrengthPolicies/00000000-0000-0000-0000-000000000004`).
- This strength accepts only phishing-resistant authenticators (e.g., FIDO2 / passkeys, Windows Hello for Business, certificate-based auth).
- It is the **only accepted grant**.

**How it blocks non-MFA:** because the phishing-resistant authentication strength is the sole grant, anything weaker is rejected — including **plain password sign-in and any non-MFA or non-phishing-resistant MFA** (e.g., SMS or app push). There is no fallback grant to fall through to, so a weak credential simply cannot complete sign-in to AWS.

**Licensing:** Entra **P1 (`AAD_PREMIUM`)** is present on the tenant, so Conditional Access is licensed and enforceable.

---

## 4. No-breaking-changes guardrail (written but disabled)

The live `delicatehug.com` tenant is shared, so the Entra-side changes must not alter how real users sign in today. To honor that guardrail, the following are **written as Terraform but disabled** behind a single flag — **`var.enable_entra_changes = false`**:

- the three Entra users (`ith-superadmin` / `ith-admin` / `ith-s3` @ `delicatehug.com`)
- the **`ITH-Interview-Admins`** group
- the **Conditional Access policy** (phishing-resistant MFA)
- the Identity Center **account assignments** (which bind users/group to the three permission sets)

> The **permission sets themselves are deployed** (they are harmless without assignments). Only the Entra objects, the group, the CA policy, and the assignments are gated.

### How to enable them in an isolated tenant

1. Use a **dedicated / isolated Entra tenant** (not a shared production tenant) so the new users and the phishing-resistant CA policy cannot affect anyone else.
2. Confirm the tenant has an **Entra P1 (`AAD_PREMIUM`)** license so Conditional Access is enforceable.
3. Set **`var.enable_entra_changes = true`** and apply. This creates the three users, the `ITH-Interview-Admins` group, the CA policy, and the account assignments.
4. **Register a phishing-resistant authenticator** (FIDO2 security key / passkey) for each user, because the CA policy will reject any sign-in that is not phishing-resistant.
5. Sign in at the access portal: **[`https://d-96677e53fe.awsapps.com/start/`](https://d-96677e53fe.awsapps.com/start/)**.

---

## 5. At a glance

| Item | Value |
|---|---|
| Login URL | [`https://d-96677e53fe.awsapps.com/start/`](https://d-96677e53fe.awsapps.com/start/) |
| Identity Center instance | `ssoins-46812a8af28769cf` |
| Identity store | `d-96677e53fe` |
| IdP / federation | Microsoft Entra → SCIM (`scim.aws.com` external ids) |
| Target account | `ith-workload` (`118821711925`) |
| Permission sets (deployed) | `ITH-SuperAdmin`, `ITH-Admin`, `ITH-S3Reader` |
| MFA control | Entra CA → built-in "Phishing-resistant MFA" auth strength |
| CA auth-strength id | `00000000-0000-0000-0000-000000000004` |
| Entra license | P1 (`AAD_PREMIUM`) |
| Enable flag | `var.enable_entra_changes` (default `false`) |

See [Requirements](../REQUIREMENTS.md) for the requirement ids referenced throughout (the VPC-only reader is path **P4**; the human web-app read path is **C1**).

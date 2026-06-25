# [01] Microsoft Entra ID

**Type:** Identity Provider (IdP)

> **In plain terms —** The company's identity provider, and where the three admin users actually live. AWS trusts it for login, so there are no AWS-local passwords to steal.

## Controls applied

- **Prevention:**
  - External IdP federated to Identity Center (SAML + SCIM)
  - CA [[04]](04-conditional-access.md) enforces phishing-resistant MFA (doc-only). Only the 3 demo users were added to the live tenant.
- **Detection:** Entra sign-in logs (tenant side).
- **Alert:** Risky / non-MFA sign-in via Entra Identity Protection (recommended, out of scope).

## What would trigger an alert

- A user signs in without phishing-resistant MFA → blocked by CA [[04]](04-conditional-access.md) once enabled; risky sign-in flagged by Entra Identity Protection (recommended).
- A new Entra user is granted the AWS app → the resulting assignment in Identity Center is caught by change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).

---
[< controls index](README.md) | [< home](../README.md)

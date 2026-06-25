# [01] Microsoft Entra ID

- **Type:** Identity Provider (IdP)
- **Requirements:** R2,R3,R10

## Controls applied

- External IdP federated into AWS IAM Identity Center via SAML + SCIM provisioning.
- Conditional Access (see [04]) is the enforcement point for phishing-resistant MFA.
- Tenant `delicatehug.com`; AAD_PREMIUM (P1) present so CA + auth strengths are licensed.
- Guardrail: no live-tenant changes were applied (Entra IaC left disabled).

---
[< controls index](README.md) | [< home](../README.md)

# [04] Conditional Access - phishing-resistant MFA

- **Type:** Entra CA policy (doc-only)
- **Requirements:** R2,R3,R10

## Controls applied

- Requires authentication strength = built-in **Phishing-resistant MFA** (`...0004`).
- Only accepted grant -> password-only / weak-MFA / **non-MFA is blocked**.
- Scoped to the interview-admins group on the AWS app.
- **Written as IaC but disabled** (`enable_entra_changes=false`) - see OutOfScopeNotes.

---
[< controls index](README.md) | [< home](../README.md)

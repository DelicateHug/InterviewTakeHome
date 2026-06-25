# [22] Per-patient KMS CMKs

- **Type:** KMS customer-managed keys (x7)
- **Requirements:** R15

## Controls applied

- **One CMK per patient**; each object encrypted under its patient's key.
- Rotation enabled; key policy grants only the 4 reader roles Decrypt/GenerateDataKey.
- Incident lever: disable one key -> exactly one patient's data goes dark.
- Tradeoff (OutOfScopeNotes): cost/sprawl vs per-subject isolation.

---
[< controls index](README.md) | [< home](../README.md)

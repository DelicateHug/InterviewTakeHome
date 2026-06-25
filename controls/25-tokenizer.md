# [25] Vaultless tokenizer

- **Type:** Build-time data pipeline
- **Requirements:** R14,R18

## Controls applied

- AES-SIV deterministic, reversible, **epoch-tagged** tokens (`tok:v1:...`) - no vault.
- Rotate-forward: new epoch DEK for new writes; old epochs retained to read old tokens.
- Produces the tokenized sensitive view + the Safe-Harbor de-identified view.
- Demo keys via HKDF; prod keys via `kms:GenerateDataKey`.

---
[< controls index](README.md) | [< home](../README.md)

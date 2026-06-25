# [38] Role-assumption IP alerter

**Type:** EventBridge + Lambda

> **In plain terms —** A small tripwire that watches every `AssumeRole` and pages if the call comes from an IP outside the approved list — catching stolen credentials being used from somewhere new.

## Controls applied

- **Prevention:** —. (Detective — it watches assumptions, it doesn't block them.)
- **Detection:** EventBridge on `sts:AssumeRole*`.
- **Alert:** Source IP outside the allow-list → SNS [36].

## What would trigger an alert

- An admin or service role is assumed from an IP outside the allow-list — e.g. an attacker reusing stolen keys from their own host → SNS [36].
- A role is assumed from an unexpected country / network → SNS [36].

---
[< controls index](README.md) | [< home](../README.md)

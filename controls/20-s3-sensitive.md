# [20] S3 sensitive bucket

**Type:** S3 bucket (phi-sensitive-<acct>)

> **In plain terms —** The bucket holding the tokenized patient data. Reads only succeed from inside the VPC (or via the access point [26]), every object is KMS-encrypted under its patient's key [22], and a human on a laptop is flatly denied — they must use the EC2 UI [28].

## Controls applied

- **Prevention:** Tokenized ePHI; per-patient SSE-KMS [22]; versioning; Block Public Access on; bucket policy denies non-TLS, outside-org, and reads unless `aws:sourceVpce` [13]/[14] or via access point [27]; humans on a laptop are denied → must use the EC2 UI [28]. Account-id suffix naming.
- **Detection:** CloudTrail S3 object-level (data) events; s3-access-denied filter [34].
- **Alert:** Blocked read → s3-access-denied alarm [35]; policy / ACL / BPA change → s3-policy-change alarm [35] + change-alerter [40].

## What would trigger an alert

- A user on a laptop (outside the VPC) tries to read an object, or an admin reads raw objects directly instead of via the EC2 UI [28] → denied → s3-access-denied alarm [35].
- Someone changes the bucket policy, an ACL, or Block Public Access → s3-policy-change alarm [35] + change-alerter [40] → SNS [36].
- A principal outside the org tries to read it → denied by RCP [08] → s3-access-denied alarm [35].

---
[< controls index](README.md) | [< home](../README.md)

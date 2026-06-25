# [20] S3 sensitive bucket

**Type:** S3 bucket (phi-sensitive-&lt;acct&gt;)

> **In plain terms —** The bucket holding the tokenized patient data. Reads only succeed from inside the VPC (or via the access point [[26]](26-access-point.md)), every object is KMS-encrypted under its patient's key [[22]](22-kms-patient.md), and a human on a laptop is flatly denied — they must use the EC2 UI [[28]](28-ec2-webapp.md).

## Controls applied

- **Prevention:**
  - Tokenized ePHI
  - per-patient SSE-KMS [[22]](22-kms-patient.md)
  - versioning
  - Block Public Access on
  - bucket policy denies non-TLS, outside-org, and reads unless `aws:sourceVpce` [[13]](13-s3-gateway-endpoint.md)/[[14]](14-s3-interface-endpoint.md) or via access point [[27]](27-lambda-redactor.md)
  - humans on a laptop are denied → must use the EC2 UI [[28]](28-ec2-webapp.md). Account-id suffix naming.
- **Detection:**
  - CloudTrail S3 object-level (data) events
  - s3-access-denied filter [[34]](34-log-group.md).
- **Alert:**
  - Blocked read → s3-access-denied alarm [[35]](35-alarms.md)
  - policy / ACL / BPA change → s3-policy-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- A user on a laptop (outside the VPC) tries to read an object, or an admin reads raw objects directly instead of via the EC2 UI [[28]](28-ec2-webapp.md) → denied → s3-access-denied alarm [[35]](35-alarms.md).
- Someone changes the bucket policy, an ACL, or Block Public Access → s3-policy-change alarm [[35]](35-alarms.md) + change-alerter [[40]](40-change-alerter.md) → SNS [[36]](36-sns.md).
- A principal outside the org tries to read it → denied by RCP [[08]](08-rcp.md) → s3-access-denied alarm [[35]](35-alarms.md).

---
[< controls index](README.md) | [< home](../README.md)

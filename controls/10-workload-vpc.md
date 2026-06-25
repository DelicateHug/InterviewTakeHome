# [10] Workload VPC

**Type:** VPC 10.20.0.0/16

> **In plain terms —** The private network the app runs in. It has no internet gateway and no NAT, so workloads reach AWS only through VPC endpoints — nothing talks to the public internet.

## Controls applied

- **Prevention:** No IGW, no NAT (fully private); 2 private subnets / 2 AZs; all AWS API access via VPC endpoints [13][14][15].
- **Detection:** CloudTrail on ec2 network changes (VPC flow logs recommended).
- **Alert:** Route / subnet change → change-alerter [40].

## What would trigger an alert

- An admin adds an internet gateway or NAT, or edits a route / subnet (opening a path to the internet) → change-alerter [40] → SNS [36].
- A security group in the VPC is changed → sg-change alarm [35] + change-alerter [40].

---
[< controls index](README.md) | [< home](../README.md)

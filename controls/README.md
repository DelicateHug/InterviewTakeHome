# Controls index

Consolidated controls for the whole system, then one tiny page per component.
The `[NN]` tags map each control to its component page below and to the
homepage diagrams. See also [OutOfScopeNotes.md](OutOfScopeNotes.md).

## Controls applied (system-wide)

**Identity & access**

- Phishing-resistant MFA at the IdP (doc-only) `[04]`
- SSO-only via permission sets `[03]`
- Least-privilege roles `[29] [31] [32]`
- No human has direct S3 — read-only via the EC2 UI `[28]`

**Org guardrails**

- S3 guardrail SCP `[07]`
- Strict account allow-list SCP `[41]`
- RCP — deny S3 outside the org `[08]`
- Block Public Access on every bucket

**Network isolation**

- Private VPC — no IGW/NAT `[10]`
- All AWS access via VPC endpoints `[13] [14] [15]`
- Security-group-as-source rules, no CIDR `[16] [17] [18]`

**Data protection**

- Per-patient SSE-KMS CMKs `[22]`
- Vaultless tokenization `[25]`
- De-identified copy `[21]`
- TLS-only everywhere

**Bucket access control**

- Bucket policy VPC-lock on `aws:sourceVpce` `[20]`
- Access-point delegation for the redactor `[26] [27]`

**Detection**

- CloudTrail — multi-region + data events `[33]`
- GuardDuty managed threat detection `[37]`
- 9 CloudWatch alarms `[35]`

**Alert & response**

- SNS security alerts `[36]`
- Role-assumption IP alerter `[38]`
- Change / CreateUser alerter with exclusion list `[40]`
- Per-patient key disable lever `[22]`

## Per-component pages

| ID | Resource | Type |
|----|----------|------|
| [01] | [Microsoft Entra ID](01-idp-entra.md) | Identity Provider (IdP) |
| [02] | [AWS IAM Identity Center](02-identity-center.md) | SSO / federation |
| [03] | [Permission sets (3)](03-permission-sets.md) | IAM Identity Center permission sets |
| [04] | [Conditional Access (phishing-resistant MFA)](04-conditional-access.md) | Entra CA policy (doc-only) |
| [05] | [Management account](05-management-account.md) | AWS Organizations mgmt acct |
| [06] | [OU InterviewTakeHome](06-ou.md) | Organizational Unit |
| [07] | [SCP (S3 guardrails)](07-scp.md) | Service Control Policy |
| [08] | [RCP (deny S3 outside org)](08-rcp.md) | Resource Control Policy |
| [09] | [Member account ith-workload](09-member-account.md) | AWS account |
| [10] | [Workload VPC](10-workload-vpc.md) | VPC 10.20.0.0/16 |
| [11] | [On-prem VPC](11-onprem-vpc.md) | VPC 192.168.0.0/16 |
| [12] | [VPC peering](12-peering.md) | VPC peering connection |
| [13] | [S3 gateway endpoint](13-s3-gateway-endpoint.md) | Gateway VPC endpoint |
| [14] | [S3 interface endpoint](14-s3-interface-endpoint.md) | Interface VPC endpoint |
| [15] | [SSM / STS / KMS / Logs endpoints](15-interface-endpoints.md) | Interface VPC endpoints |
| [16] | [Endpoints security group](16-endpoints-sg.md) | Security group |
| [17] | [App security group](17-app-sg.md) | Security group |
| [18] | [On-prem node security group](18-onprem-sg.md) | Security group |
| [19] | [On-prem internet gateway](19-igw-onprem.md) | Internet gateway |
| [20] | [S3 sensitive bucket](20-s3-sensitive.md) | S3 bucket (phi-sensitive-<acct>) |
| [21] | [S3 de-identified bucket](21-s3-deident.md) | S3 bucket (phi-deident-<acct>) |
| [22] | [Per-patient KMS CMKs](22-kms-patient.md) | KMS customer-managed keys (x7) |
| [23] | [De-identified KMS CMK](23-kms-deident.md) | KMS customer-managed key |
| [24] | [Logs / notifications KMS CMK](24-kms-logs.md) | KMS customer-managed key |
| [25] | [Vaultless tokenizer](25-tokenizer.md) | Build-time data pipeline |
| [26] | [S3 access point](26-access-point.md) | S3 access point |
| [27] | [Lambda redactor (basic reader)](27-lambda-redactor.md) | Lambda + IAM Function URL |
| [28] | [EC2 web app](28-ec2-webapp.md) | EC2 instance (human read path) |
| [29] | [EC2 instance role](29-ec2-role.md) | IAM role |
| [30] | [On-prem k3s node](30-onprem-node.md) | EC2 + k3s (Kubernetes) |
| [31] | [On-prem node role](31-onprem-role.md) | IAM role |
| [32] | [s3 user role](32-s3-reader-role.md) | IAM role (the 's3' principal) |
| [33] | [CloudTrail](33-cloudtrail.md) | CloudTrail trail (ith-trail) |
| [34] | [CloudWatch Logs + metric filters](34-log-group.md) | Log group + 11 metric filters |
| [35] | [CloudWatch alarms (9)](35-alarms.md) | CloudWatch alarms |
| [36] | [SNS security alerts](36-sns.md) | SNS topic |
| [37] | [GuardDuty](37-guardduty.md) | GuardDuty detector |
| [38] | [Role-assumption IP alerter](38-ip-alerter.md) | EventBridge + Lambda |
| [39] | [CloudTrail log bucket](39-ct-bucket.md) | S3 bucket (ith-cloudtrail-<acct>) |
| [40] | [Change / CreateUser alerter](40-change-alerter.md) | CloudWatch metric filters + alarms (2) |
| [41] | [Strict account allow-list SCP](41-account-scp.md) | Service Control Policy |

[< home](../README.md)

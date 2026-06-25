# Controls index

One page per component ID (matches the homepage Mermaid diagram). Each lists the
controls applied to that resource. See also [OutOfScopeNotes.md](OutOfScopeNotes.md).

| ID | Resource | Type | Page | Requirements |
|----|----------|------|------|--------------|
| [01] | Microsoft Entra ID | Identity Provider (IdP) | [01-idp-entra.md](01-idp-entra.md) | R2,R3,R10 |
| [02] | AWS IAM Identity Center | SSO / federation | [02-identity-center.md](02-identity-center.md) | R13 |
| [03] | Permission sets (3) | IAM Identity Center permission sets | [03-permission-sets.md](03-permission-sets.md) | R13,C1 |
| [04] | Conditional Access - phishing-resistant MFA | Entra CA policy (doc-only) | [04-conditional-access.md](04-conditional-access.md) | R2,R3,R10 |
| [05] | Management account | AWS Organizations mgmt acct | [05-management-account.md](05-management-account.md) | R6 |
| [06] | OU InterviewTakeHome | Organizational Unit | [06-ou.md](06-ou.md) | R6 |
| [07] | SCP - S3 guardrails | Service Control Policy | [07-scp.md](07-scp.md) | R8 |
| [08] | RCP - deny S3 outside org | Resource Control Policy | [08-rcp.md](08-rcp.md) | R9 |
| [09] | Member account ith-workload | AWS account | [09-member-account.md](09-member-account.md) | R6 |
| [10] | Workload VPC | VPC 10.20.0.0/16 | [10-workload-vpc.md](10-workload-vpc.md) | R16 |
| [11] | On-prem VPC | VPC 192.168.0.0/16 | [11-onprem-vpc.md](11-onprem-vpc.md) | R16 |
| [12] | VPC peering | VPC peering connection | [12-peering.md](12-peering.md) | R16 |
| [13] | S3 gateway endpoint | Gateway VPC endpoint | [13-s3-gateway-endpoint.md](13-s3-gateway-endpoint.md) | R16 |
| [14] | S3 interface endpoint | Interface VPC endpoint | [14-s3-interface-endpoint.md](14-s3-interface-endpoint.md) | R16 |
| [15] | SSM / STS / KMS / Logs endpoints | Interface VPC endpoints | [15-interface-endpoints.md](15-interface-endpoints.md) | R16 |
| [16] | Endpoints security group | Security group | [16-endpoints-sg.md](16-endpoints-sg.md) | R17 |
| [17] | App security group | Security group | [17-app-sg.md](17-app-sg.md) | R17 |
| [18] | On-prem node security group | Security group | [18-onprem-sg.md](18-onprem-sg.md) | R17 |
| [19] | On-prem internet gateway | Internet gateway | [19-igw-onprem.md](19-igw-onprem.md) | R16 |
| [20] | S3 sensitive bucket | S3 bucket (phi-sensitive-<acct>) | [20-s3-sensitive.md](20-s3-sensitive.md) | R1,R7,C1 |
| [21] | S3 de-identified bucket | S3 bucket (phi-deident-<acct>) | [21-s3-deident.md](21-s3-deident.md) | R7,C4 |
| [22] | Per-patient KMS CMKs | KMS customer-managed keys (x7) | [22-kms-patient.md](22-kms-patient.md) | R15 |
| [23] | De-identified KMS CMK | KMS customer-managed key | [23-kms-deident.md](23-kms-deident.md) | R15,C4 |
| [24] | Logs / notifications KMS CMK | KMS customer-managed key | [24-kms-logs.md](24-kms-logs.md) | R11 |
| [25] | Vaultless tokenizer | Build-time data pipeline | [25-tokenizer.md](25-tokenizer.md) | R14,R18 |
| [26] | S3 access point | S3 access point (ith-sensitive-ap) | [26-access-point.md](26-access-point.md) | P1 |
| [27] | Lambda redactor (basic reader) | Lambda + IAM Function URL | [27-lambda-redactor.md](27-lambda-redactor.md) | R16,C2 |
| [28] | EC2 web app | EC2 instance (the human read path) | [28-ec2-webapp.md](28-ec2-webapp.md) | R16,C1,C3 |
| [29] | EC2 instance role | IAM role | [29-ec2-role.md](29-ec2-role.md) | R13 |
| [30] | On-prem k3s node | EC2 + k3s (Kubernetes) | [30-onprem-node.md](30-onprem-node.md) | R16 |
| [31] | On-prem node role | IAM role | [31-onprem-role.md](31-onprem-role.md) | R13 |
| [32] | s3 user role | IAM role (the 's3' principal) | [32-s3-reader-role.md](32-s3-reader-role.md) | R13 |
| [33] | CloudTrail | CloudTrail trail (ith-trail) | [33-cloudtrail.md](33-cloudtrail.md) | R11 |
| [34] | CloudWatch Logs + metric filters | Log group + 9 metric filters | [34-log-group.md](34-log-group.md) | R4 |
| [35] | CloudWatch alarms (9) | CloudWatch alarms | [35-alarms.md](35-alarms.md) | R4 |
| [36] | SNS security alerts | SNS topic | [36-sns.md](36-sns.md) | R4 |
| [37] | GuardDuty | GuardDuty detector | [37-guardduty.md](37-guardduty.md) | R11 |
| [38] | Role-assumption IP alerter | EventBridge + Lambda | [38-ip-alerter.md](38-ip-alerter.md) | R12 |
| [39] | CloudTrail log bucket | S3 bucket (ith-cloudtrail-<acct>) | [39-ct-bucket.md](39-ct-bucket.md) | R11 |

[< home](../README.md)

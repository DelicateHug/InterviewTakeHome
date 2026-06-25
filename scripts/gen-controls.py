#!/usr/bin/env python3
"""Generate controls/[NN]-<slug>.md (one page per component ID) + controls/README.md.
Terse, bullet-point controls per resource. IDs here are the CANONICAL scheme used by the
homepage Mermaid diagram. Re-run after editing COMPONENTS."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "controls"))

# id, slug, name, type, reqs, path, controls[]
COMPONENTS = [
    # ---- Identity ----
    ("01", "idp-entra", "Microsoft Entra ID", "Identity Provider (IdP)", "R2,R3,R10",
     "", [
        "External IdP federated into AWS IAM Identity Center via SAML + SCIM provisioning.",
        "Conditional Access (see [04]) is the enforcement point for phishing-resistant MFA.",
        "Tenant `delicatehug.com`; AAD_PREMIUM (P1) present so CA + auth strengths are licensed.",
        "Guardrail: no live-tenant changes were applied (Entra IaC left disabled).",
     ]),
    ("02", "identity-center", "AWS IAM Identity Center", "SSO / federation", "R13",
     "", [
        "Single login portal: https://d-96677e53fe.awsapps.com/start/",
        "Identity source = external Entra (SCIM); no local passwords.",
        "Access granted only via permission sets [03] assigned to the workload account [09].",
     ]),
    ("03", "permission-sets", "Permission sets (3)", "IAM Identity Center permission sets", "R13,C1",
     "", [
        "`ITH-SuperAdmin`: AdministratorAccess (all, incl. KMS).",
        "`ITH-Admin`: relevant services, **explicit `Deny kms:*`**.",
        "`ITH-S3Reader`: S3 read on the PHI buckets **only when `aws:sourceVpce`** matches [13].",
        "Created for real (inert until assigned); 1h session.",
     ]),
    ("04", "conditional-access", "Conditional Access - phishing-resistant MFA", "Entra CA policy (doc-only)", "R2,R3,R10",
     "", [
        "Requires authentication strength = built-in **Phishing-resistant MFA** (`...0004`).",
        "Only accepted grant -> password-only / weak-MFA / **non-MFA is blocked**.",
        "Scoped to the interview-admins group on the AWS app.",
        "**Written as IaC but disabled** (`enable_entra_changes=false`) - see OutOfScopeNotes.",
     ]),
    # ---- Org / guardrails ----
    ("05", "management-account", "Management account", "AWS Organizations mgmt acct", "R6",
     "", [
        "Org `o-ncxqr8pp2c`; both SCP and RCP policy types enabled on root.",
        "Holds Identity Center; assumes OrganizationAccountAccessRole into [09] to deploy.",
        "Not subject to SCPs (AWS rule) - workload isolated in a member account instead.",
     ]),
    ("06", "ou", "OU InterviewTakeHome", "Organizational Unit", "R6",
     "", [
        "Dedicated isolation boundary; `ou-33e3-5p8xygxw`.",
        "SCP [07] and RCP [08] attach **here only** - existing accounts untouched.",
     ]),
    ("07", "scp", "SCP - S3 guardrails", "Service Control Policy", "R8",
     "", [
        "Deny all S3 when `aws:SecureTransport=false` (TLS required).",
        "Deny `PutObject` to `phi-*` without `x-amz-server-side-encryption=aws:kms`.",
        "Deny `PutObject` to `phi-*` when the SSE header is absent.",
        "Deny `PutAccountPublicAccessBlock` except the deploy role.",
     ]),
    ("08", "rcp", "RCP - deny S3 outside org", "Resource Control Policy", "R9",
     "", [
        "Deny `s3:*` when `aws:PrincipalOrgID != o-ncxqr8pp2c` (resource-side).",
        "Excludes AWS service principals (`aws:PrincipalIsAWSService`).",
        "Stops confused-deputy / cross-account access even if a bucket policy were mis-set.",
     ]),
    ("09", "member-account", "Member account ith-workload", "AWS account", "R6",
     "", [
        "Account `118821711925` - dedicated blast radius for all workload resources.",
        "`close_on_deletion=true` (90-day suspension window on teardown).",
     ]),
    # ---- Network ----
    ("10", "workload-vpc", "Workload VPC", "VPC 10.20.0.0/16", "R16",
     "", [
        "**No IGW, no NAT** - fully private; 2 private subnets across 2 AZs.",
        "All AWS API access via VPC endpoints [13][14][15].",
     ]),
    ("11", "onprem-vpc", "On-prem VPC", "VPC 192.168.0.0/16", "R16", "P2", [
        "Represents an on-prem datacenter; has an IGW [19] for egress (k3s install).",
        "Reaches the data tier only via peering [12] + the S3 interface endpoint [14].",
     ]),
    ("12", "peering", "VPC peering", "VPC peering connection", "R16", "P2", [
        "Routes both ways between [10] and [11].",
        "**Tradeoff:** peering is non-transitive & N^2; Transit Gateway is the scalable successor.",
        "Gateway endpoints are NOT reachable across peering -> on-prem must use the interface endpoint.",
     ]),
    ("13", "s3-gateway-endpoint", "S3 gateway endpoint", "Gateway VPC endpoint", "R16",
     "P3,P4", [
        "Route-table endpoint for in-VPC S3 (EC2 web app, s3-reader).",
        "Requests carry `aws:sourceVpce` = this id -> satisfies the bucket VPC-lock.",
     ]),
    ("14", "s3-interface-endpoint", "S3 interface endpoint", "Interface VPC endpoint", "R16",
     "P2", [
        "PrivateLink S3 reachable across the peering by the on-prem node.",
        "Private DNS disabled (so it doesn't shadow the gateway endpoint in-VPC).",
        "Use the `bucket.vpce-...` TLS name for SAN match.",
     ]),
    ("15", "interface-endpoints", "SSM / STS / KMS / Logs endpoints", "Interface VPC endpoints", "R16",
     "", [
        "ssm, ssmmessages, ec2messages (Session Manager), sts, kms, logs.",
        "Keep the workload VPC internet-free; SG-restricted to 443 from app/on-prem SGs.",
        "Note: a missing endpoint silently falls back to public - all are provisioned.",
     ]),
    ("16", "endpoints-sg", "Endpoints security group", "Security group", "R17",
     "", [
        "Ingress 443 **from the app SG [17]** (SG-as-source, not CIDR).",
        "Ingress 443 **from the on-prem node SG [18]** (cross-VPC SG reference over peering).",
     ]),
    ("17", "app-sg", "App security group", "Security group", "R17", "P3", [
        "**No inbound** - the web app is reached only via SSM port-forward.",
        "Egress 443 to the endpoints SG [16] and to the S3 gateway prefix list.",
     ]),
    ("18", "onprem-sg", "On-prem node security group", "Security group", "R17", "P2", [
        "No inbound (SSM only); egress to internet (k3s) + S3 interface endpoint.",
     ]),
    ("19", "igw-onprem", "On-prem internet gateway", "Internet gateway", "R16", "P2", [
        "Datacenter egress for the on-prem VPC (k3s installer, image pulls).",
        "PHI reads still go private via the interface endpoint over peering.",
     ]),
    # ---- Data / crypto ----
    ("20", "s3-sensitive", "S3 sensitive bucket", "S3 bucket (phi-sensitive-<acct>)", "R1,R7,C1",
     "P1,P2,P3,P4", [
        "Holds tokenized ePHI; per-patient SSE-KMS [22]; versioning; Block Public Access on.",
        "Bucket policy: deny non-TLS; deny outside-org; **deny reads unless `aws:sourceVpce` [13]/[14] or via access point [27]**.",
        "Effect: humans on a laptop are denied -> must use the EC2 UI [28] (C1). Deploy role exempted for management.",
        "Account-id suffix naming (R7).",
     ]),
    ("21", "s3-deident", "S3 de-identified bucket", "S3 bucket (phi-deident-<acct>)", "R7,C4",
     "", [
        "Holds the Safe-Harbor de-identified copy; readable anywhere **in the org**.",
        "Still org-locked (RCP [08]), TLS-only, SSE-KMS [23], Block Public Access on.",
     ]),
    ("22", "kms-patient", "Per-patient KMS CMKs", "KMS customer-managed keys (x7)", "R15",
     "", [
        "**One CMK per patient**; each object encrypted under its patient's key.",
        "Rotation enabled; key policy grants only the 4 reader roles Decrypt/GenerateDataKey.",
        "Incident lever: disable one key -> exactly one patient's data goes dark.",
        "Tradeoff (OutOfScopeNotes): cost/sprawl vs per-subject isolation.",
     ]),
    ("23", "kms-deident", "De-identified KMS CMK", "KMS customer-managed key", "R15,C4",
     "", ["Encrypts the de-identified bucket [21]; rotation enabled."]),
    ("24", "kms-logs", "Logs / notifications KMS CMK", "KMS customer-managed key", "R11",
     "", ["Encrypts CloudTrail [31], CloudWatch Logs [32], and the SNS topic [35]."]),
    ("25", "tokenizer", "Vaultless tokenizer", "Build-time data pipeline", "R14,R18",
     "", [
        "AES-SIV deterministic, reversible, **epoch-tagged** tokens (`tok:v1:...`) - no vault.",
        "Rotate-forward: new epoch DEK for new writes; old epochs retained to read old tokens.",
        "Produces the tokenized sensitive view + the Safe-Harbor de-identified view.",
        "Demo keys via HKDF; prod keys via `kms:GenerateDataKey`.",
     ]),
    # ---- Paths / compute ----
    ("26", "access-point", "S3 access point", "S3 access point (ith-sensitive-ap)", "P1",
     "P1", [
        "Standard access point the redactor [27] reads through.",
        "Bucket policy delegates to same-account access points (the access-point branch of the VPC-lock).",
     ]),
    ("27", "lambda-redactor", "Lambda redactor (basic reader)", "Lambda + IAM Function URL", "R16,C2",
     "P1", [
        "Reads via the access point [26], strips all identifiers, returns **non-sensitive only**.",
        "IAM-auth Function URL = the 'access point' the basic reader calls.",
        "Substitute for S3 Object Lambda (AWS-gated for new accounts) - same outcome.",
     ]),
    ("28", "ec2-webapp", "EC2 web app", "EC2 instance (the human read path)", "R16,C1,C3",
     "P3", [
        "**Only** human read path; all 3 admins read details here.",
        "**SSM-only**: no key pair, no SSH, no public IP; IMDSv2 required.",
        "Pure-stdlib SigV4 app (no pip/boto3) on :8080; reads via gateway endpoint [13].",
        "Identifiers stay tokenized even in the UI.",
     ]),
    ("29", "ec2-role", "EC2 instance role", "IAM role", "R13", "P3", [
        "Least privilege: S3 read on the buckets + `kms:Decrypt` + SSM core.",
        "The web app uses this role; humans never get direct S3 (C1).",
     ]),
    ("30", "onprem-node", "On-prem k3s node", "EC2 + k3s (Kubernetes)", "R16", "P2", [
        "Single-node k3s; a CronJob reads S3 across peering via the interface endpoint [14].",
        "Pod uses the node role [31] via IMDS (hop limit 2); SSM-managed (no SSH).",
     ]),
    ("31", "onprem-role", "On-prem node role", "IAM role", "R13", "P2", [
        "S3 read on the sensitive bucket + `kms:Decrypt` + SSM core.",
     ]),
    ("32", "s3-reader-role", "s3 user role", "IAM role (the 's3' principal)", "R13", "P4", [
        "Can `GetObject`, but the bucket policy denies unless `aws:sourceVpce` matches.",
        "Verified: assume from laptop -> AccessDenied; in-VPC -> allowed.",
     ]),
    # ---- Detection / response ----
    ("33", "cloudtrail", "CloudTrail", "CloudTrail trail (ith-trail)", "R11",
     "", [
        "Multi-region; log-file validation; KMS-encrypted [24]; -> log bucket [37] + CW Logs [34].",
        "S3 object-level (data) events on both buckets.",
     ]),
    ("34", "log-group", "CloudWatch Logs + metric filters", "Log group + 9 metric filters", "R4",
     "", ["Trail log group `/ith/cloudtrail`; 9 metric filters feed the alarms [35]."]),
    ("35", "alarms", "CloudWatch alarms (9)", "CloudWatch alarms", "R4",
     "", [
        "root-usage, console-no-mfa, unauthorized-api, iam-policy-change, s3-policy-change,",
        "kms-disable-delete, cloudtrail-change, sg-change, s3-access-denied -> SNS [36].",
        "3 already fired on real activity during the build.",
     ]),
    ("36", "sns", "SNS security alerts", "SNS topic", "R4",
     "", [
        "`ith-security-alerts`, KMS-encrypted; all alarms + GuardDuty + IP-alerter publish here.",
        "Email subscription must be **confirmed** to receive alerts.",
     ]),
    ("37", "guardduty", "GuardDuty", "GuardDuty detector", "R11",
     "", ["Threat detection enabled; findings (severity>=4) -> EventBridge -> SNS [36]."]),
    ("38", "ip-alerter", "Role-assumption IP alerter", "EventBridge + Lambda", "R12",
     "", [
        "EventBridge on `sts:AssumeRole*` -> Lambda checks source IP vs allow-list -> SNS.",
        "Alerts on any external IP outside the allow-list (empty default = alert-all for the demo).",
     ]),
    ("39", "ct-bucket", "CloudTrail log bucket", "S3 bucket (ith-cloudtrail-<acct>)", "R11",
     "", ["SSE-KMS [24]; Block Public Access on; CloudTrail-service write only; TLS-only."]),
]


def page(c):
    cid, slug, name, typ, reqs, path, controls = c
    lines = [f"# [{cid}] {name}", ""]
    lines.append(f"- **Type:** {typ}")
    lines.append(f"- **Requirements:** {reqs}")
    if path:
        lines.append(f"- **Path:** {path}")
    lines += ["", "## Controls applied", ""]
    lines += [f"- {b}" for b in controls]
    lines += ["", "---", "[< controls index](README.md) | [< home](../README.md)", ""]
    return "\n".join(lines)


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for c in COMPONENTS:
        cid, slug, name, typ, reqs, path, _ = c
        fname = f"{cid}-{slug}.md"
        with open(os.path.join(OUT, fname), "w", encoding="utf-8") as f:
            f.write(page(c))
        rows.append(f"| [{cid}] | {name} | {typ} | [{fname}]({fname}) | {reqs} |")

    idx = ["# Controls index", "",
           "One page per component ID (matches the homepage Mermaid diagram). Each lists the",
           "controls applied to that resource. See also [OutOfScopeNotes.md](OutOfScopeNotes.md).",
           "", "| ID | Resource | Type | Page | Requirements |",
           "|----|----------|------|------|--------------|"]
    idx += rows
    idx += ["", "[< home](../README.md)", ""]
    with open(os.path.join(OUT, "README.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(idx))
    print(f"wrote {len(COMPONENTS)} control pages + README.md to {OUT}")


if __name__ == "__main__":
    main()

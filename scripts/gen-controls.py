#!/usr/bin/env python3
"""Generate controls/[NN]-<slug>.md (one page per component ID) + controls/README.md.

Each page is intentionally tiny: Type + the controls applied, bucketed as
Prevention / Detection / Alert. IDs are the CANONICAL scheme used by the homepage
Mermaid diagrams. Re-run after editing COMPONENTS."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "controls"))

DASH = "—"  # em dash, used for "not applicable"

# id, slug, name, type, prevention, detection, alert
COMPONENTS = [
    # ---- Identity ----
    ("01", "idp-entra", "Microsoft Entra ID", "Identity Provider (IdP)",
     "External IdP federated to Identity Center (SAML + SCIM); CA [04] enforces phishing-resistant MFA (doc-only). Only the 3 demo users were added to the live tenant.",
     "Entra sign-in logs (tenant side).",
     "Risky / non-MFA sign-in via Entra Identity Protection (recommended, out of scope)."),
    ("02", "identity-center", "AWS IAM Identity Center", "SSO / federation",
     "Single sign-in portal; identity source = Entra via SCIM (no local passwords); access only through permission sets [03].",
     "CloudTrail [33] logs assignment + permission-set changes.",
     "Assignment / permission-set change -> change-alerter [40]."),
    ("03", "permission-sets", "Permission sets (3)", "IAM Identity Center permission sets",
     "`ITH-SuperAdmin` (all), `ITH-Admin` (Deny `kms:*`), `ITH-S3Reader` (S3 read only when `aws:sourceVpce` [13]); 1h session; further capped by the account SCP [41].",
     "CloudTrail logs use and edits.",
     "Edit -> change-alerter [40]; AccessDenied -> unauthorized-api alarm [35]."),
    ("04", "conditional-access", "Conditional Access (phishing-resistant MFA)", "Entra CA policy (doc-only)",
     "Requires auth strength = built-in **Phishing-resistant MFA** (`...0004`); the only accepted grant, so non-MFA / weak MFA is blocked. Written as IaC but **disabled** (guardrail).",
     "Entra sign-in logs.",
     "Entra Identity Protection (recommended)."),
    # ---- Org / guardrails ----
    ("05", "management-account", "Management account", "AWS Organizations mgmt acct",
     "Org root with SCP + RCP enabled; holds Identity Center; assumes OrganizationAccountAccessRole into [09]. Not subject to SCPs, so the workload is isolated in a member account.",
     "Org CloudTrail; root-usage metric filter [34].",
     "Any root use -> root-usage alarm [35] -> SNS [36]."),
    ("06", "ou", "OU InterviewTakeHome", "Organizational Unit",
     "Isolation boundary `ou-33e3-5p8xygxw`; SCP [07] + RCP [08] attach here only, so existing accounts are untouched.",
     "Org CloudTrail on policy attach/detach.",
     "Attach / detach -> change-alerter [40]."),
    ("07", "scp", "SCP (S3 guardrails)", "Service Control Policy",
     "Deny non-TLS S3; deny PHI `PutObject` without SSE-KMS; protect account Block-Public-Access. Even account admins cannot override.",
     "Org CloudTrail on policy changes.",
     "Policy change -> change-alerter [40]."),
    ("08", "rcp", "RCP (deny S3 outside org)", "Resource Control Policy",
     "Resource-side deny of `s3:*` when `aws:PrincipalOrgID` != this org (AWS services excluded). Stops external / confused-deputy access even if a bucket policy were mis-set.",
     "Org CloudTrail on policy changes.",
     "Policy change -> change-alerter [40]."),
    ("09", "member-account", "Member account ith-workload", "AWS account",
     "Account `118821711925`: dedicated blast radius; the strict allow-list SCP [41] caps it to demo-only services; `close_on_deletion=true`.",
     "Account CloudTrail [33].",
     "See per-resource alerts + change-alerter [40]."),
    # ---- Network ----
    ("10", "workload-vpc", "Workload VPC", "VPC 10.20.0.0/16",
     "No IGW, no NAT (fully private); 2 private subnets / 2 AZs; all AWS API access via VPC endpoints [13][14][15].",
     "CloudTrail on ec2 network changes (VPC flow logs recommended).",
     "Route / subnet change -> change-alerter [40]."),
    ("11", "onprem-vpc", "On-prem VPC", "VPC 192.168.0.0/16",
     "Simulated datacenter; reaches the data tier only via peering [12] + the S3 interface endpoint [14].",
     "CloudTrail.",
     "Network change -> change-alerter [40]."),
    ("12", "peering", "VPC peering", "VPC peering connection",
     "Routes both ways between [10] and [11]; gateway endpoints are NOT reachable across peering (forces the interface endpoint). Tradeoff: non-transitive & N^2; TGW is the successor.",
     "CloudTrail on peering changes.",
     "Peering change -> change-alerter [40]."),
    ("13", "s3-gateway-endpoint", "S3 gateway endpoint", "Gateway VPC endpoint",
     "In-VPC S3 for the EC2 app [28] and s3 user [32]; requests carry `aws:sourceVpce` = this id, satisfying the bucket VPC-lock [20].",
     "CloudTrail.",
     "Endpoint / policy change -> change-alerter [40]."),
    ("14", "s3-interface-endpoint", "S3 interface endpoint", "Interface VPC endpoint",
     "PrivateLink S3 reachable across peering by the on-prem node; private DNS disabled; use the `bucket.vpce-...` TLS name for SAN match.",
     "CloudTrail.",
     "Endpoint / policy change -> change-alerter [40]."),
    ("15", "interface-endpoints", "SSM / STS / KMS / Logs endpoints", "Interface VPC endpoints",
     "ssm, ssmmessages, ec2messages, sts, kms, logs - keep the VPC internet-free; SG-restricted to 443 from the app / on-prem SGs.",
     "CloudTrail.",
     "Endpoint / policy change -> change-alerter [40]."),
    ("16", "endpoints-sg", "Endpoints security group", "Security group",
     "Ingress 443 from the app SG [17] and the on-prem node SG [18] - SG-as-source, no CIDR.",
     "CloudTrail; sg-change metric filter [34].",
     "SG change -> sg-change alarm [35] + change-alerter [40]."),
    ("17", "app-sg", "App security group", "Security group",
     "No inbound (reached only via SSM port-forward); egress 443 to the endpoints SG [16] + S3 gateway prefix list.",
     "CloudTrail; sg-change filter [34].",
     "SG change -> sg-change alarm [35] + change-alerter [40]."),
    ("18", "onprem-sg", "On-prem node security group", "Security group",
     "No inbound (SSM only); egress to internet (k3s) + the S3 interface endpoint.",
     "CloudTrail; sg-change filter [34].",
     "SG change -> sg-change alarm [35] + change-alerter [40]."),
    ("19", "igw-onprem", "On-prem internet gateway", "Internet gateway",
     "Datacenter egress for the on-prem VPC only; PHI reads still go private via the interface endpoint over peering.",
     "CloudTrail.",
     "Change -> change-alerter [40]."),
    # ---- Data / crypto ----
    ("20", "s3-sensitive", "S3 sensitive bucket", "S3 bucket (phi-sensitive-<acct>)",
     "Tokenized ePHI; per-patient SSE-KMS [22]; versioning; Block Public Access on; bucket policy denies non-TLS, outside-org, and reads unless `aws:sourceVpce` [13]/[14] or via access point [27]; humans on a laptop are denied -> must use the EC2 UI [28]. Account-id suffix naming.",
     "CloudTrail S3 object-level (data) events; s3-access-denied filter [34].",
     "Blocked read -> s3-access-denied alarm [35]; policy / ACL / BPA change -> s3-policy-change alarm [35] + change-alerter [40]."),
    ("21", "s3-deident", "S3 de-identified bucket", "S3 bucket (phi-deident-<acct>)",
     "Safe-Harbor de-identified copy, readable anywhere in the org; still org-locked (RCP [08]), TLS-only, SSE-KMS [23], Block Public Access on.",
     "CloudTrail S3 data events.",
     "Policy change -> s3-policy-change alarm [35] + change-alerter [40]."),
    ("22", "kms-patient", "Per-patient KMS CMKs", "KMS customer-managed keys (x7)",
     "One CMK per patient (object encrypted under its patient's key); rotation on; key policy grants only the 4 reader roles `Decrypt`/`GenerateDataKey`. Response lever: disable one key -> exactly one patient goes dark.",
     "CloudTrail kms events; kms-disable-delete filter [34].",
     "DisableKey / ScheduleKeyDeletion -> kms-disable-delete alarm [35]."),
    ("23", "kms-deident", "De-identified KMS CMK", "KMS customer-managed key",
     "Encrypts the de-identified bucket [21]; rotation on.",
     "CloudTrail kms events.",
     "DisableKey / ScheduleKeyDeletion -> kms-disable-delete alarm [35]."),
    ("24", "kms-logs", "Logs / notifications KMS CMK", "KMS customer-managed key",
     "Encrypts CloudTrail [33], CloudWatch Logs [34], and the SNS topic [36].",
     "CloudTrail kms events.",
     "DisableKey / ScheduleKeyDeletion -> kms-disable-delete alarm [35]."),
    ("25", "tokenizer", "Vaultless tokenizer", "Build-time data pipeline",
     "AES-SIV deterministic, reversible, epoch-tagged tokens (no vault); rotate-forward; produces the tokenized sensitive view + the Safe-Harbor de-identified view.",
     DASH + " (off-cloud build step).",
     DASH + "."),
    # ---- Paths / compute ----
    ("26", "access-point", "S3 access point", "S3 access point",
     "Standard access point the redactor [27] reads through; the bucket policy delegates to same-account access points.",
     "CloudTrail.",
     "AP / policy change -> change-alerter [40]."),
    ("27", "lambda-redactor", "Lambda redactor (basic reader)", "Lambda + IAM Function URL",
     "Reads via the access point [26], strips all identifiers, returns **non-sensitive only**; IAM-auth Function URL is the 'access point' the basic reader calls.",
     "CloudTrail lambda + invoke events.",
     "Code / config / policy change -> change-alerter [40]."),
    ("28", "ec2-webapp", "EC2 web app", "EC2 instance (human read path)",
     "The **only** human read path (all 3 admins); SSM-only (no key pair / SSH / public IP); IMDSv2; pure-stdlib SigV4 app reads via the gateway endpoint [13]; identifiers stay tokenized in the UI.",
     "CloudTrail; SSM session logging.",
     "Instance / SG change -> change-alerter [40]."),
    ("29", "ec2-role", "EC2 instance role", "IAM role",
     "Least privilege: S3 read on the buckets + `kms:Decrypt` + SSM core. The app uses this role; humans never get direct S3.",
     "CloudTrail; iam-policy-change filter [34].",
     "Role / policy change -> iam-policy-change alarm [35] + change-alerter [40]."),
    ("30", "onprem-node", "On-prem k3s node", "EC2 + k3s (Kubernetes)",
     "Single-node k3s; a CronJob reads S3 across peering via the interface endpoint [14]; IMDS hop-limit 2; SSM-managed (no SSH).",
     "CloudTrail; SSM session logging.",
     "Instance / SG change -> change-alerter [40]."),
    ("31", "onprem-role", "On-prem node role", "IAM role",
     "Least privilege: S3 read on the sensitive bucket + `kms:Decrypt` + SSM core.",
     "CloudTrail; iam-policy-change filter [34].",
     "Role / policy change -> iam-policy-change alarm [35] + change-alerter [40]."),
    ("32", "s3-reader-role", "s3 user role", "IAM role (the 's3' principal)",
     "Can `GetObject`, but the bucket policy denies unless `aws:sourceVpce` matches. Verified: assume from laptop -> AccessDenied; in-VPC -> allowed.",
     "CloudTrail; s3-access-denied filter [34].",
     "AccessDenied -> s3-access-denied alarm [35]; role change -> change-alerter [40]."),
    # ---- Detection / response ----
    ("33", "cloudtrail", "CloudTrail", "CloudTrail trail (ith-trail)",
     "Multi-region; log-file validation; KMS-encrypted [24]; management + S3 data events; -> log bucket [39] + CloudWatch Logs [34].",
     "This is the primary detection source for the whole account.",
     "StopLogging / DeleteTrail / UpdateTrail -> cloudtrail-change alarm [35]."),
    ("34", "log-group", "CloudWatch Logs + metric filters", "Log group + 11 metric filters",
     "Trail log group `/ith/cloudtrail`, KMS-encrypted (aggregates multi-region + global IAM events).",
     "11 metric filters (9 baseline + 2 exclusion-based [40]) turn log patterns into metrics.",
     "Metrics feed the alarms [35]."),
    ("35", "alarms", "CloudWatch alarms (9)", "CloudWatch alarms",
     DASH + ".",
     "root-usage, console-no-mfa, unauthorized-api, iam-policy-change, s3-policy-change, kms-disable-delete, cloudtrail-change, sg-change, s3-access-denied.",
     "Any alarm -> SNS [36] (3 already fired on real activity during the build)."),
    ("36", "sns", "SNS security alerts", "SNS topic",
     "KMS-encrypted topic; publishers restricted to CloudWatch + EventBridge + the account.",
     DASH + ".",
     "Delivery channel for all alarms [35] + GuardDuty [37] + IP-alerter [38] + change-alerter [40] (email must be confirmed)."),
    ("37", "guardduty", "GuardDuty", "GuardDuty detector",
     DASH + ".",
     "Managed threat detection enabled.",
     "Findings severity >= 4 -> EventBridge -> SNS [36]."),
    ("38", "ip-alerter", "Role-assumption IP alerter", "EventBridge + Lambda",
     DASH + ".",
     "EventBridge on `sts:AssumeRole*`.",
     "Source IP outside the allow-list -> SNS [36]."),
    ("39", "ct-bucket", "CloudTrail log bucket", "S3 bucket (ith-cloudtrail-<acct>)",
     "SSE-KMS [24]; Block Public Access on; CloudTrail-service write only; TLS-only.",
     "CloudTrail.",
     "Policy change -> s3-policy-change alarm [35] + change-alerter [40]."),
    # ---- New controls (this iteration) ----
    ("40", "change-alerter", "Change / CreateUser alerter", "CloudWatch metric filters + alarms (2)",
     DASH + " (detective / responsive).",
     "Two metric filters on the trail log group [34]: `iam:CreateUser`, and any mutating event (`readOnly=false`). Reads from CloudWatch Logs so global IAM events are caught regardless of region.",
     "Fires only when the actor is **not on the exclusion list** (default: SuperAdmin [03] + the deploy role) -> alarm -> SNS [36]; CreateUser has its own named alarm."),
    ("41", "account-scp", "Strict account allow-list SCP", "Service Control Policy",
     "Denies **all** actions except the services this demo needs (s3, kms, ec2, lambda, ssm + messages, sts, iam, cloudtrail, guardduty, cloudwatch, logs, sns, events, tag). Attached to the account [09]; caps even SuperAdmin.",
     "Org CloudTrail on policy changes.",
     "Policy change -> change-alerter [40]."),
]

# Consolidated, deduplicated controls for the whole system (shown above the index table).
# Each domain is a list of (control, refs) — one short claim per line, refs tucked at the end.
CONSOLIDATED = [
    ("Identity & access", [
        ("Phishing-resistant MFA at the IdP (doc-only)", "[04]"),
        ("SSO-only via permission sets", "[03]"),
        ("Least-privilege roles", "[29] [31] [32]"),
        ("No human has direct S3 — read-only via the EC2 UI", "[28]"),
    ]),
    ("Org guardrails", [
        ("S3 guardrail SCP", "[07]"),
        ("Strict account allow-list SCP", "[41]"),
        ("RCP — deny S3 outside the org", "[08]"),
        ("Block Public Access on every bucket", ""),
    ]),
    ("Network isolation", [
        ("Private VPC — no IGW/NAT", "[10]"),
        ("All AWS access via VPC endpoints", "[13] [14] [15]"),
        ("Security-group-as-source rules, no CIDR", "[16] [17] [18]"),
    ]),
    ("Data protection", [
        ("Per-patient SSE-KMS CMKs", "[22]"),
        ("Vaultless tokenization", "[25]"),
        ("De-identified copy", "[21]"),
        ("TLS-only everywhere", ""),
    ]),
    ("Bucket access control", [
        ("Bucket policy VPC-lock on `aws:sourceVpce`", "[20]"),
        ("Access-point delegation for the redactor", "[26] [27]"),
    ]),
    ("Detection", [
        ("CloudTrail — multi-region + data events", "[33]"),
        ("GuardDuty managed threat detection", "[37]"),
        ("9 CloudWatch alarms", "[35]"),
    ]),
    ("Alert & response", [
        ("SNS security alerts", "[36]"),
        ("Role-assumption IP alerter", "[38]"),
        ("Change / CreateUser alerter with exclusion list", "[40]"),
        ("Per-patient key disable lever", "[22]"),
    ]),
]


def page(c):
    cid, slug, name, typ, prev, det, alert = c
    return "\n".join([
        f"# [{cid}] {name}", "",
        f"- **Type:** {typ}", "",
        "## Controls applied", "",
        f"- **Prevention:** {prev}",
        f"- **Detection:** {det}",
        f"- **Alert:** {alert}", "",
        "---",
        "[< controls index](README.md) | [< home](../README.md)", "",
    ])


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for c in COMPONENTS:
        cid, slug, name, typ = c[0], c[1], c[2], c[3]
        fname = f"{cid}-{slug}.md"
        with open(os.path.join(OUT, fname), "w", encoding="utf-8") as f:
            f.write(page(c))
        rows.append(f"| [{cid}] | [{name}]({fname}) | {typ} |")

    idx = ["# Controls index", "",
           "Consolidated controls for the whole system, then one tiny page per component.",
           "The `[NN]` tags map each control to its component page below and to the",
           "homepage diagrams. See also [OutOfScopeNotes.md](OutOfScopeNotes.md).", "",
           "## Controls applied (system-wide)", ""]
    for theme, controls in CONSOLIDATED:
        idx.append(f"**{theme}**")
        idx.append("")
        for text, refs in controls:
            tag = f" `{refs}`" if refs else ""
            idx.append(f"- {text}{tag}")
        idx.append("")
    idx += ["## Per-component pages", "",
            "| ID | Resource | Type |",
            "|----|----------|------|"]
    idx += rows
    idx += ["", "[< home](../README.md)", ""]
    with open(os.path.join(OUT, "README.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(idx))
    print(f"wrote {len(COMPONENTS)} control pages + README.md to {OUT}")


if __name__ == "__main__":
    main()

# =====================================================================================
# R13 (AWS side) — the 3 Identity Center PERMISSION SETS, created for real. They are inert
# templates until assigned (assignments.tf), so creating them is additive and non-breaking.
#   ITH-SuperAdmin : AdministratorAccess, but a permissions boundary [42] caps the MAX to
#                    everything-EXCEPT-kms:* (ceiling by intersection, no Deny)
#   ITH-Admin      : relevant services, EXPLICITLY denies all kms:*
#   ITH-S3Reader   : read the PHI buckets ONLY from inside the VPC (aws:sourceVpce)
#
# Three different ways KMS gets blocked, on purpose, to show they are NOT the same lever:
#   SuperAdmin -> permissions boundary [42] (caps the principal's MAX; KMS outside ceiling)
#   Admin      -> inline `Deny kms:*`        (explicit deny in the identity policy)
#   (account)  -> SCP [41]                    (org guardrail allow-list on the whole account)
# =====================================================================================

data "aws_ssoadmin_instances" "this" {}

# Pull the workload bucket/vpce ids so the S3Reader policy can pin aws:sourceVpce.
data "terraform_remote_state" "workload" {
  backend = "local"
  config  = { path = "${path.module}/../20-workload/terraform.tfstate" }
}

locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  ps_count          = var.create_permission_sets ? 1 : 0

  gw_vpce          = try(data.terraform_remote_state.workload.outputs.s3_gateway_vpce_id, "vpce-PLACEHOLDER")
  sensitive_bucket = try(data.terraform_remote_state.workload.outputs.sensitive_bucket, "phi-sensitive-118821711925")
  deident_bucket   = try(data.terraform_remote_state.workload.outputs.deident_bucket, "phi-deident-118821711925")

  # [42] customer-managed boundary policy NAME, created in the member account by 20-workload.
  # Identity Center references the boundary by name (must exist in the target account).
  superadmin_boundary_name = try(data.terraform_remote_state.workload.outputs.superadmin_boundary_policy_name, "ITH-SuperAdmin-Boundary")
}

# ---- ITH-SuperAdmin -----------------------------------------------------------------
resource "aws_ssoadmin_permission_set" "superadmin" {
  count            = local.ps_count
  name             = "ITH-SuperAdmin"
  description      = "Full administrator, capped by permissions boundary [42] to everything-except-kms:*"
  instance_arn     = local.instance_arn
  session_duration = "PT1H"
}

resource "aws_ssoadmin_managed_policy_attachment" "superadmin_admin" {
  count              = local.ps_count
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.superadmin[0].arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# [42] Permissions boundary on ITH-SuperAdmin — the showcase control.
# The boundary CAPS the maximum permissions of the SSO role this permission set provisions:
#   effective = AdministratorAccess (Allow *)  ∩  boundary (Allow NotAction kms:*)
#             = everything EXCEPT kms:*
# KMS is denied with NO Deny statement anywhere — it simply isn't inside the ceiling. That
# is the property that makes a permissions boundary different from ITH-Admin's explicit
# `Deny kms:*` and from the org SCP [41]. The boundary policy itself is a customer-managed
# IAM policy created in the member account (20-workload/iam.tf); IAM Identity Center
# references it BY NAME and requires it to exist in every account the PS is provisioned to.
resource "aws_ssoadmin_permissions_boundary_attachment" "superadmin" {
  count              = local.ps_count
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.superadmin[0].arn

  permissions_boundary {
    customer_managed_policy_reference {
      name = local.superadmin_boundary_name
      path = "/"
    }
  }
}

# ---- ITH-Admin (relevant services, NO kms) ------------------------------------------
resource "aws_ssoadmin_permission_set" "admin" {
  count            = local.ps_count
  name             = "ITH-Admin"
  description      = "Relevant services; explicitly denied all kms:*"
  instance_arn     = local.instance_arn
  session_duration = "PT1H"
}

resource "aws_ssoadmin_permission_set_inline_policy" "admin" {
  count              = local.ps_count
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin[0].arn
  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RelevantServices"
        Effect = "Allow"
        Action = [
          "s3:*", "ec2:*", "cloudwatch:*", "logs:*", "cloudtrail:*",
          "guardduty:*", "sns:*", "ssm:*", "iam:Get*", "iam:List*"
        ]
        Resource = "*"
      },
      {
        Sid      = "NoKmsForAdmin"
        Effect   = "Deny"
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

# ---- ITH-S3Reader (read PHI buckets only from inside the VPC) ------------------------
resource "aws_ssoadmin_permission_set" "s3reader" {
  count            = local.ps_count
  name             = "ITH-S3Reader"
  description      = "Read the PHI buckets only when inside the VPC (aws:sourceVpce)"
  instance_arn     = local.instance_arn
  session_duration = "PT1H"
}

resource "aws_ssoadmin_permission_set_inline_policy" "s3reader" {
  count              = local.ps_count
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.s3reader[0].arn
  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadPhiFromVpcOnly"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${local.sensitive_bucket}", "arn:aws:s3:::${local.sensitive_bucket}/*",
          "arn:aws:s3:::${local.deident_bucket}", "arn:aws:s3:::${local.deident_bucket}/*"
        ]
        Condition = { StringEquals = { "aws:sourceVpce" = local.gw_vpce } }
      },
      {
        Sid      = "DecryptPhi"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = "*"
      }
    ]
  })
}

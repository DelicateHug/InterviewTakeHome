# =====================================================================================
# 00-org : the org plumbing the brief asks for —
#   one management account  ->  one OU  ->  one member account inside it.
# SCP + RCP (policies.tf) attach ONLY to this new OU, so existing accounts are untouched.
# =====================================================================================

data "aws_organizations_organization" "this" {}

locals {
  root_id = data.aws_organizations_organization.this.roots[0].id
  org_id  = data.aws_organizations_organization.this.id

  tags = {
    Project   = "InterviewTakeHome"
    ManagedBy = "Terraform"
    Stack     = "00-org"
    Owner     = "interview-takehome"
  }
}

# The dedicated, isolated OU. Everything blast-radius-relevant hangs off here.
resource "aws_organizations_organizational_unit" "ith" {
  name      = var.ou_name
  parent_id = local.root_id
  tags      = local.tags
}

# The single new member account ("inside ou one account").
# Organizations auto-creates an OrganizationAccountAccessRole the mgmt account can assume;
# the 20-workload stack assumes that role to deploy into this account.
resource "aws_organizations_account" "workload" {
  name      = var.account_name
  email     = var.account_email
  parent_id = aws_organizations_organizational_unit.ith.id
  role_name = "OrganizationAccountAccessRole"

  # Teardown convenience: `terraform destroy` will request account closure.
  # NOTE: AWS account closure is a 90-day SUSPENDED window (documented in scripts/teardown.md).
  close_on_deletion          = true
  iam_user_access_to_billing = "ALLOW"

  tags = local.tags

  lifecycle {
    ignore_changes = [role_name] # avoid spurious diffs if AWS normalizes it
  }
}

# Deploys INTO the new member account by assuming the OrganizationAccountAccessRole
# that Organizations created (00-org). Base credentials come from the mgmt SSO profile.
provider "aws" {
  region  = var.region
  profile = var.mgmt_profile

  assume_role {
    role_arn     = "arn:aws:iam::${var.workload_account_id}:role/OrganizationAccountAccessRole"
    session_name = "ith-workload-deploy"
  }

  default_tags {
    tags = local.tags
  }
}

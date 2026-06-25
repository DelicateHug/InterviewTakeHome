# AWS provider runs against the MANAGEMENT account (Identity Center lives there).
provider "aws" {
  profile = var.mgmt_profile
  region  = var.region
  default_tags {
    tags = {
      Project   = "InterviewTakeHome"
      ManagedBy = "Terraform"
      Stack     = "10-identity"
    }
  }
}

# Entra provider uses your existing `az login` session. It is only acted upon when
# var.enable_entra_changes = true; with it false (the default) no Entra resources or
# data sources are evaluated, so the live tenant is never touched.
provider "azuread" {
  tenant_id = var.tenant_id
  use_cli   = true
}

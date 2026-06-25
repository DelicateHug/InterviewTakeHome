# =====================================================================================
# Account assignments (user -> permission set -> workload account). DOC-ONLY: gated on
# enable_entra_changes because the principal ids come from the SCIM-provisioned identity
# store, which only exists once the Entra users are created + synced. With Entra disabled,
# nothing here is evaluated.
#
# Flow when enabled:
#   1) azuread_user (entra.tf) created + added to the AWS app's group
#   2) SCIM provisions them into Identity Center (data.aws_identitystore_user finds them)
#   3) these assignments bind each user to its permission set on the workload account
# =====================================================================================

data "aws_identitystore_user" "u" {
  for_each          = local.entra_users
  identity_store_id = local.identity_store_id
  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = "${each.value.upn}@${var.tenant_domain}"
    }
  }
}

locals {
  permission_set_arns = var.create_permission_sets ? {
    "ITH-SuperAdmin" = aws_ssoadmin_permission_set.superadmin[0].arn
    "ITH-Admin"      = aws_ssoadmin_permission_set.admin[0].arn
    "ITH-S3Reader"   = aws_ssoadmin_permission_set.s3reader[0].arn
  } : {}
  workload_account_id = try(data.terraform_remote_state.workload.outputs.workload_account_id, "118821711925")
}

resource "aws_ssoadmin_account_assignment" "u" {
  for_each           = local.entra_users
  instance_arn       = local.instance_arn
  permission_set_arn = local.permission_set_arns[each.value.ps]

  principal_id   = data.aws_identitystore_user.u[each.key].user_id
  principal_type = "USER"

  target_id   = local.workload_account_id
  target_type = "AWS_ACCOUNT"
}

# ---- Owner assignment (makes the new account visible/usable in the SSO portal) -------
data "aws_identitystore_user" "owner" {
  count             = var.assign_owner_superadmin && var.create_permission_sets ? 1 : 0
  identity_store_id = local.identity_store_id
  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = var.owner_username
    }
  }
}

resource "aws_ssoadmin_account_assignment" "owner_superadmin" {
  count              = var.assign_owner_superadmin && var.create_permission_sets ? 1 : 0
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.superadmin[0].arn
  principal_id       = data.aws_identitystore_user.owner[0].user_id
  principal_type     = "USER"
  target_id          = local.workload_account_id
  target_type        = "AWS_ACCOUNT"
}

# ---- Demo user assignments (SSO) -----------------------------------------------------
# The 3 interview users are created in Entra via the az CLI and SCIM-provisioned into
# Identity Center. These bind each user to its permission set on the workload account.
# Gated on assign_demo_users (the data lookups need the users to already exist in the
# identity store). Deliberately DECOUPLED from enable_entra_changes so it never creates or
# modifies anything in the Entra tenant - it only consumes already-provisioned users.
locals {
  demo_user_assignments = var.assign_demo_users && var.create_permission_sets ? {
    "ith-superadmin" = "ITH-SuperAdmin"
    "ith-admin"      = "ITH-Admin"
    "ith-s3"         = "ITH-S3Reader"
  } : {}
}

data "aws_identitystore_user" "demo" {
  for_each          = local.demo_user_assignments
  identity_store_id = local.identity_store_id
  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = "${each.key}@${var.tenant_domain}"
    }
  }
}

resource "aws_ssoadmin_account_assignment" "demo" {
  for_each           = local.demo_user_assignments
  instance_arn       = local.instance_arn
  permission_set_arn = local.permission_set_arns[each.value]
  principal_id       = data.aws_identitystore_user.demo[each.key].user_id
  principal_type     = "USER"
  target_id          = local.workload_account_id
  target_type        = "AWS_ACCOUNT"
}

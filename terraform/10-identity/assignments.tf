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

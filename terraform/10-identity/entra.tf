# =====================================================================================
# R2 / R3 / R10 / R13 (Entra side) — DOC-ONLY by default (enable_entra_changes = false).
# This is the complete IaC for: the 3 interview users, the admin group, and the
# Conditional Access policy that REQUIRES phishing-resistant MFA and thereby BLOCKS
# non-MFA / weaker auth. It is left disabled so the live tenant is not changed; flip the
# toggle in an isolated tenant to apply. See docs/identity-and-mfa.md.
# =====================================================================================

locals {
  # Built-in Entra "Phishing-resistant MFA" authentication strength (fixed GUID),
  # expressed as the full policy resource path the azuread provider expects.
  phishing_resistant_strength_id = "/policies/authenticationStrengthPolicies/00000000-0000-0000-0000-000000000004"

  users = {
    superadmin = { upn = "ith-superadmin", display = "ITH Super Admin", ps = "ITH-SuperAdmin" }
    admin      = { upn = "ith-admin", display = "ITH Admin (no KMS)", ps = "ITH-Admin" }
    s3         = { upn = "ith-s3", display = "ITH S3 Reader (VPC-only)", ps = "ITH-S3Reader" }
  }
  entra_users = var.enable_entra_changes ? local.users : {}
  entra_count = var.enable_entra_changes ? 1 : 0
}

resource "azuread_group" "admins" {
  count            = local.entra_count
  display_name     = "ITH-Interview-Admins"
  security_enabled = true
}

resource "azuread_user" "u" {
  for_each              = local.entra_users
  user_principal_name   = "${each.value.upn}@${var.tenant_domain}"
  display_name          = each.value.display
  mail_nickname         = each.value.upn
  password              = "ChangeMe-${each.key}-${substr(var.tenant_id, 0, 8)}!" # forced reset on first sign-in
  force_password_change = true
}

resource "azuread_group_member" "u" {
  for_each         = local.entra_users
  group_object_id  = azuread_group.admins[0].object_id
  member_object_id = azuread_user.u[each.key].object_id
}

# Phishing-resistant MFA for the interview admins on the AWS app; non-MFA is blocked
# because the ONLY accepted grant is the phishing-resistant strength.
resource "azuread_conditional_access_policy" "phishing_resistant" {
  count        = local.entra_count
  display_name = "ITH - Require phishing-resistant MFA for AWS admins"
  state        = "enabled"

  conditions {
    client_app_types = ["all"]
    applications {
      included_applications = [var.aws_app_id]
    }
    users {
      included_groups = [azuread_group.admins[0].object_id]
    }
  }

  grant_controls {
    operator                          = "OR"
    authentication_strength_policy_id = local.phishing_resistant_strength_id
  }
}

output "login_url" {
  description = "AWS access portal (README page 1)."
  value       = var.login_url
}

output "identity_center_instance_arn" {
  value = local.instance_arn
}

output "permission_sets" {
  description = "The 3 permission sets (created when create_permission_sets = true)."
  value = var.create_permission_sets ? {
    "ITH-SuperAdmin" = aws_ssoadmin_permission_set.superadmin[0].arn
    "ITH-Admin"      = aws_ssoadmin_permission_set.admin[0].arn
    "ITH-S3Reader"   = aws_ssoadmin_permission_set.s3reader[0].arn
  } : {}
}

output "entra_enabled" {
  description = "Whether the Entra users + Conditional Access were applied (guardrail)."
  value       = var.enable_entra_changes
}

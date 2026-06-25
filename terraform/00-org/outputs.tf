output "org_id" {
  description = "AWS Organization ID (used by the RCP and workload bucket policies)."
  value       = local.org_id
}

output "root_id" {
  value = local.root_id
}

output "ou_id" {
  description = "The isolated InterviewTakeHome OU."
  value       = aws_organizations_organizational_unit.ith.id
}

output "workload_account_id" {
  description = "The new member account that hosts the workload (consumed by 10/20 stacks)."
  value       = aws_organizations_account.workload.id
}

output "workload_account_email" {
  value = aws_organizations_account.workload.email
}

output "deploy_role_arn" {
  description = "Role the 20-workload stack assumes to deploy into the new account."
  value       = "arn:aws:iam::${aws_organizations_account.workload.id}:role/OrganizationAccountAccessRole"
}

output "scp_id" {
  value = aws_organizations_policy.scp_s3_guardrails.id
}

output "rcp_id" {
  value = aws_organizations_policy.rcp_s3_org_only.id
}

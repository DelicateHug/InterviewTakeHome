output "workload_account_id" {
  value = local.account_id
}

output "sensitive_bucket" {
  value = aws_s3_bucket.sensitive.id
}

output "deident_bucket" {
  value = aws_s3_bucket.deident.id
}

output "cloudtrail_bucket" {
  value = aws_s3_bucket.cloudtrail.id
}

output "redactor_function_url" {
  description = "P1 - IAM-signed GET <url>?key=patients/<id>.json returns redacted (non-sensitive) data."
  value       = aws_lambda_function_url.redactor.function_url
}

output "sensitive_access_point_arn" {
  value = aws_s3_access_point.sensitive.arn
}

output "webapp_instance_id" {
  description = "P3 — SSM into this for the web UI (port-forward 8080)."
  value       = aws_instance.webapp.id
}

output "onprem_instance_id" {
  description = "P2 — the on-prem k3s node."
  value       = aws_instance.onprem.id
}

output "s3_gateway_vpce_id" {
  value = aws_vpc_endpoint.s3_gw.id
}

output "superadmin_boundary_policy_name" {
  description = "[42] Customer-managed permissions boundary capping ITH-SuperAdmin to everything-except-kms:*. The SSO boundary attachment in 10-identity references this by name."
  value       = aws_iam_policy.superadmin_boundary.name
}

output "s3_interface_vpce_dns" {
  value = aws_vpc_endpoint.s3_interface.dns_entry[0].dns_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "patient_key_aliases" {
  description = "Per-patient KMS key aliases (R15)."
  value       = { for k, v in aws_kms_alias.patient : k => v.name }
}

output "ssm_webapp_portforward_hint" {
  value = "aws ssm start-session --target ${aws_instance.webapp.id} --document-name AWS-StartPortForwardingSession --parameters portNumber=8080,localPortNumber=8080 --profile ith-workload --region ${local.region}  # then open http://localhost:8080"
}

# ---- P5 attested enclave ------------------------------------------------------------
output "enclave_key_alias" {
  description = "P5 — attestation-gated CMK; unlocks only for the measured enclave (PCR0)."
  value       = aws_kms_alias.enclave.name
}

output "enclave_pcr0_param" {
  description = "P5 — SSM param the node publishes its enclave PCR0 to (two-phase deploy)."
  value       = local.enclave_pcr0_param
}

output "enclave_pcr0_locked" {
  description = "P5 — the PCR0 currently locked into the enclave key policy ('' = phase A, unlocked)."
  value       = var.enclave_pcr0
}

output "enclave_demo_hint" {
  description = "P5 — see the attested read/write round-trip + the negative (no-attestation) test."
  value = join("\n", [
    "# round-trip pod logs (WROTE / READ_OK):",
    "aws ssm start-session --target ${aws_instance.onprem.id} --profile ith-workload --region ${local.region} --document-name AWS-StartInteractiveCommand --parameters command='kubectl logs job/phi-rw-enclave'",
    "# negative test — node role, NO enclave attestation -> AccessDenied:",
    "aws kms generate-data-key --key-id ${aws_kms_alias.enclave.name} --key-spec AES_256 --profile ith-workload --region ${local.region}",
  ])
}

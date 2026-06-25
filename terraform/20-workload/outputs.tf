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

output "object_lambda_access_point_arn" {
  description = "P1 — invoke GetObject on this OLAP to get redacted (non-sensitive) data."
  value       = aws_s3control_object_lambda_access_point.redactor.arn
}

output "object_lambda_access_point_alias" {
  value = aws_s3control_object_lambda_access_point.redactor.alias
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

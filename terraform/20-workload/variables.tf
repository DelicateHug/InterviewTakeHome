variable "mgmt_profile" {
  description = "Base AWS profile (mgmt SSO) used to assume into the workload account."
  type        = string
  default     = "ith-mgmt"
}

variable "workload_account_id" {
  description = "New member account id (output workload_account_id from 00-org)."
  type        = string
  default     = "118821711925"
}

variable "org_id" {
  description = "AWS Organization id (output org_id from 00-org); used in bucket policies."
  type        = string
  default     = "o-ncxqr8pp2c"
}

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "alert_email" {
  description = "Email subscribed to the security SNS topic (all alarms). Confirm the subscription."
  type        = string
  default     = "dylanheathsmart@gmail.com"
}

variable "allowed_assume_role_cidrs" {
  description = <<-EOT
    Source IP CIDRs considered "expected" for human role assumptions. The IP-based
    alerter (R12) fires when an AssumeRole/AssumeRoleWithSAML comes from outside these.
    Default is empty on purpose for the demo so the alarm DEMONSTRABLY fires; in
    production set this to your admin egress ranges.
  EOT
  type        = list(string)
  default     = []
}

variable "key_rotation_enabled" {
  description = "Enable annual rotation on the per-patient CMKs."
  type        = bool
  default     = true
}

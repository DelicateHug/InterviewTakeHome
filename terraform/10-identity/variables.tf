variable "mgmt_profile" {
  type    = string
  default = "ith-mgmt"
}

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "create_permission_sets" {
  description = "Create the 3 Identity Center permission sets (inert until assigned)."
  type        = bool
  default     = true
}

# -------------------------------------------------------------------------------------
# ENTRA GUARDRAIL: everything Entra-side is OFF by default. With this false, no Entra
# users, Conditional Access, or account assignments are created or even read -> the live
# delicatehug.com tenant is not modified. Documented as "suggested, not enabled".
# -------------------------------------------------------------------------------------
variable "enable_entra_changes" {
  type    = bool
  default = false
}

variable "tenant_id" {
  type    = string
  default = "16a0c46e-e66c-4544-acb5-237c7d29e036"
}

variable "tenant_domain" {
  type    = string
  default = "delicatehug.com"
}

variable "aws_app_id" {
  description = <<-EOT
    Object id of the existing 'AWS IAM Identity Center' enterprise app in Entra, used to
    scope the Conditional Access policy. Only needed when enable_entra_changes = true.
    Find it: az ad sp list --display-name "AWS" --query "[].id".
  EOT
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}

variable "login_url" {
  description = "AWS access portal (documented on README page 1)."
  type        = string
  default     = "https://d-96677e53fe.awsapps.com/start/"
}

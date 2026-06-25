variable "aws_profile" {
  description = "AWS CLI/SSO profile with admin in the ORG MANAGEMENT account."
  type        = string
  default     = "ith-mgmt"
}

variable "region" {
  description = "Provider session region."
  type        = string
  default     = "ap-southeast-1"
}

variable "ou_name" {
  description = "Name of the dedicated, isolated OU to create under the org root."
  type        = string
  default     = "InterviewTakeHome"
}

variable "account_name" {
  description = "Name of the new member account created inside the OU."
  type        = string
  default     = "ith-workload"
}

variable "account_email" {
  description = <<-EOT
    Unique root email for the new member account. Gmail '+' subaddressing keeps it
    unique while delivering to the same inbox. MUST not collide with an existing
    account email in the org.
  EOT
  type        = string
  default     = "dylanheathsmart+ith-workload@gmail.com"
}

variable "detection_admin_principal_arns" {
  description = <<-EOT
    Principal ARNs allowed to MODIFY the detection stack (CloudWatch alarms/metric filters,
    the trail log group, the SNS topic, EventBridge rules, GuardDuty, CloudTrail). Everyone
    else - including ITH-SuperAdmin - is denied by the protect-detection SCP [60], so the
    monitors cannot be silently disabled. Defaults to the IaC deploy role only; break-glass
    stays available from the management account via this same role. In production add the
    security team's role ARN here, or switch the SCP condition to aws:PrincipalTag/team=security.
  EOT
  type        = list(string)
  default     = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
}

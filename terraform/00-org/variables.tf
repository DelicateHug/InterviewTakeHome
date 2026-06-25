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

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

variable "key_rotation_enabled" {
  description = "Enable annual rotation on the per-patient CMKs."
  type        = bool
  default     = true
}

# ---- P5 attested-enclave path -------------------------------------------------------
variable "enclave_instance_type" {
  description = <<-EOT
    Instance type for the on-prem k8s node. MUST be Nitro-Enclave-capable (>=4 vCPU,
    *.xlarge). t3.small does NOT support enclaves. Default c6i.xlarge.
  EOT
  type        = string
  default     = "c6i.xlarge"
}

variable "enclave_pcr0" {
  description = <<-EOT
    PCR0 measurement (SHA384 hex) of the enclave image (EIF). The enclave KMS key [43]
    grants Decrypt/GenerateDataKey ONLY when kms:RecipientAttestation:PCR0 equals this
    value. Two-phase deploy: leave "" for the first apply (key is root-only / unusable),
    then read the value the node publishes to SSM (/ith/enclave/pcr0) and re-apply with
    -var enclave_pcr0=<value>. scripts/deploy-enclave.ps1 automates this.
  EOT
  type        = string
  default     = ""
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = var.region
  org_id     = var.org_id

  # Inter-account naming suffix (R7): the account id makes the names globally unique
  # AND traceable to the owning account.
  sensitive_bucket  = "phi-sensitive-${local.account_id}"
  deident_bucket    = "phi-deident-${local.account_id}"
  cloudtrail_bucket = "ith-cloudtrail-${local.account_id}"
  s3logs_bucket     = "ith-s3logs-${local.account_id}"

  # Patient set (drives per-patient CMKs and uploads). key => {patient_id, key_id, ...}
  patient_index = jsondecode(file("${path.module}/../../data/patient-index.json"))
  patients      = { for p in local.patient_index.patients : p.patient_id => p }

  # P5 — SSM parameter the node publishes its enclave PCR0 to (two-phase deploy).
  enclave_pcr0_param = "/ith/enclave/pcr0"

  tags = {
    Project   = "InterviewTakeHome"
    ManagedBy = "Terraform"
    Stack     = "20-workload"
    Owner     = "interview-takehome"
  }
}

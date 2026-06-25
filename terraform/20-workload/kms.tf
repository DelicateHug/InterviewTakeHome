# =====================================================================================
# R15 — KMS "per person": ONE customer-managed CMK PER PATIENT.
#   Compliance upside : per-subject crypto blast radius; disable one key -> exactly one
#                       patient's data goes dark; per-key CloudTrail = per-patient audit.
#   Cost/ops downside : ~$1/key/month + key sprawl (see docs/tradeoffs-and-out-of-scope.md).
# Also: a deident CMK (bucket 2) and a logs/notifications CMK (CloudTrail/Logs/SNS).
# =====================================================================================

locals {
  root_arn = "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"
}

# ---- per-patient CMKs ---------------------------------------------------------------
resource "aws_kms_key" "patient" {
  for_each = local.patients

  description             = "ITH per-patient CMK — patient ${each.key}"
  enable_key_rotation     = var.key_rotation_enabled
  deletion_window_in_days = 7
  multi_region            = false

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "ith-patient-key-policy"
    Statement = [
      {
        Sid       = "RootAccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = local.root_arn }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowDataPlaneReaders"
        Effect    = "Allow"
        Principal = { AWS = local.reader_role_arns }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
      }
    ]
  })

  tags = { PatientId = each.key }
}

resource "aws_kms_alias" "patient" {
  for_each      = local.patients
  name          = "alias/ith/patient/${each.value.key_id}"
  target_key_id = aws_kms_key.patient[each.key].key_id
}

# ---- de-identified bucket CMK (bucket 2; still KMS per R1/R15 spirit) ----------------
resource "aws_kms_key" "deident" {
  description             = "ITH de-identified data CMK (bucket 2)"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "RootAccountAdmin", Effect = "Allow", Principal = { AWS = local.root_arn }, Action = "kms:*", Resource = "*" },
      {
        Sid       = "AllowDataPlaneReaders"
        Effect    = "Allow"
        Principal = { AWS = local.reader_role_arns }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "deident" {
  name          = "alias/ith/deident"
  target_key_id = aws_kms_key.deident.key_id
}

# ---- logs / notifications CMK (CloudTrail, CloudWatch Logs, SNS) ---------------------
resource "aws_kms_key" "logs" {
  description             = "ITH logs & notifications CMK (CloudTrail / Logs / SNS)"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "RootAccountAdmin", Effect = "Allow", Principal = { AWS = local.root_arn }, Action = "kms:*", Resource = "*" },
      {
        Sid       = "AllowCloudTrail"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:DescribeKey", "kms:Decrypt"]
        Resource  = "*"
        Condition = {
          StringLike = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:${data.aws_partition.current.partition}:cloudtrail:*:${local.account_id}:trail/*" }
        }
      },
      {
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:*" }
        }
      },
      {
        Sid       = "AllowSNS"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
      },
      {
        Sid       = "AllowAlarmAndEventPublishers"
        Effect    = "Allow"
        Principal = { Service = ["cloudwatch.amazonaws.com", "events.amazonaws.com"] }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "logs" {
  name          = "alias/ith/logs"
  target_key_id = aws_kms_key.logs.key_id
}

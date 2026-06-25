# =====================================================================================
# R8  SCP  — org-level S3 guardrails (attached to the OU only)
# R9  RCP  — deny S3 to any principal OUTSIDE this organization (attached to the OU only)
# =====================================================================================

# ---- R8: Service Control Policy : S3 guardrails -------------------------------------
# Demonstrates an org-enforced S3 posture that even account admins cannot override.
# Scoped so it does NOT break this stack's own Terraform deploys or AWS log delivery:
#   - TLS required for ALL S3 (every call we make is HTTPS anyway)
#   - SSE-KMS required on PutObject to the DATA buckets (phi-*) only — log buckets exempt
#   - account-level Block-Public-Access changes locked to the deploy role
resource "aws_organizations_policy" "scp_s3_guardrails" {
  name        = "ith-scp-s3-guardrails"
  description = "S3 org guardrails: enforce TLS, SSE-KMS on PHI puts, protect BPA."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Action    = "s3:*"
        Resource  = "*"
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid      = "DenyUnencryptedPhiUploads"
        Effect   = "Deny"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::phi-*/*"
        Condition = {
          StringNotEquals = { "s3:x-amz-server-side-encryption" = "aws:kms" }
        }
      },
      {
        Sid      = "DenyMissingSseHeaderOnPhi"
        Effect   = "Deny"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::phi-*/*"
        Condition = {
          Null = { "s3:x-amz-server-side-encryption" = "true" }
        }
      },
      {
        Sid      = "ProtectAccountPublicAccessBlock"
        Effect   = "Deny"
        Action   = "s3:PutAccountPublicAccessBlock"
        Resource = "*"
        Condition = {
          ArnNotLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:role/OrganizationAccountAccessRole"
          }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_organizations_policy_attachment" "scp_to_ou" {
  policy_id = aws_organizations_policy.scp_s3_guardrails.id
  target_id = aws_organizations_organizational_unit.ith.id
}

# ---- R9: Resource Control Policy : S3 only reachable from inside THIS org ------------
# RCPs evaluate on the RESOURCE side, so this blocks confused-deputy / external-principal
# access to our S3 even if a bucket policy were ever mis-set. AWS service principals are
# excluded (BoolIfExists aws:PrincipalIsAWSService) so log delivery / replication still work.
resource "aws_organizations_policy" "rcp_s3_org_only" {
  name        = "ith-rcp-s3-org-only"
  description = "Deny S3 access to any principal outside this AWS organization."
  type        = "RESOURCE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyS3OutsideOrg"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = "*"
        Condition = {
          StringNotEqualsIfExists = { "aws:PrincipalOrgID" = local.org_id }
          BoolIfExists            = { "aws:PrincipalIsAWSService" = "false" }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_organizations_policy_attachment" "rcp_to_ou" {
  policy_id = aws_organizations_policy.rcp_s3_org_only.id
  target_id = aws_organizations_organizational_unit.ith.id
}

# ---- Strict allow-list SCP : restrict the ITH account to demo-only services ----------
# "Deny everything except what this demo needs." Implemented as an Allow-list SCP: the
# effective permission is the INTERSECTION with the root FullAWSAccess, so only the listed
# service namespaces are usable - by ANY principal in the account, including SuperAdmin and
# the deploy role. The list is exactly the services this stack creates + runs:
#   data/crypto: s3, kms          compute: ec2, lambda, ssm(+messages), ec2messages
#   identity:    iam, sts         detection: cloudtrail, guardduty, cloudwatch, logs, sns, events
#   misc:        tag (resource tagging used across the above)
# Anything else (rds, dynamodb, etc.) is implicitly denied. Attached to the ACCOUNT, not the OU.
resource "aws_organizations_policy" "scp_account_allowlist" {
  name        = "ith-scp-account-allowlist"
  description = "Restrict the ITH account to only the services this demo needs."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowDemoServicesOnly"
        Effect = "Allow"
        Action = [
          "s3:*", "kms:*", "ec2:*", "lambda:*",
          "ssm:*", "ssmmessages:*", "ec2messages:*",
          "iam:*", "sts:*", "tag:*",
          "cloudtrail:*", "guardduty:*", "cloudwatch:*",
          "logs:*", "sns:*", "events:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

resource "aws_organizations_policy_attachment" "scp_allowlist_to_account" {
  policy_id = aws_organizations_policy.scp_account_allowlist.id
  target_id = aws_organizations_account.workload.id
}

# ---- [60] Protect the detection stack : deny tampering with the monitors -------------
# "Who watches the watchers." Detection you can silently delete is not detection. Even
# SuperAdmin must not be able to delete an alarm, drop a metric filter, mute the SNS topic,
# disable an EventBridge rule, stop CloudTrail, or kill GuardDuty. This Deny caps EVERY
# principal in the account except var.detection_admin_principal_arns (the IaC deploy role) on
# the detection-stack-mutating actions. Deny wins over the allow-list SCP [41], so it holds even
# though [41] grants cloudwatch:* / logs:* / sns:* / events:* / guardduty:* / cloudtrail:*.
#
# Pairs with the detection-tampering alarm [60] in 20-workload: SCP PREVENTS, alarm DETECTS if a
# break-glass actor (mgmt account via OrganizationAccountAccessRole) ever bypasses it.
#
# Why no resource tag: in THIS single-purpose account the ONLY cloudwatch/logs/sns/events/
# guardduty/cloudtrail resources ARE the detection stack, so a blanket action deny is exact. In a
# SHARED account you would instead gate these actions on aws:ResourceTag/<protect>=detection AND
# also deny <svc>:TagResource/UntagResource of that key (else an attacker untags the resource
# first, then mutates it - the tag is only as strong as your ability to keep it on).
resource "aws_organizations_policy" "scp_protect_detection" {
  name        = "ith-scp-protect-detection"
  description = "Deny tampering with the detection stack (alarms/filters/SNS/EventBridge/GuardDuty/CloudTrail) by anyone but the deploy role."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ProtectDetectionStack"
        Effect = "Deny"
        Action = [
          "cloudwatch:DeleteAlarms", "cloudwatch:PutMetricAlarm",
          "cloudwatch:DisableAlarmActions", "cloudwatch:SetAlarmState",
          "logs:DeleteMetricFilter", "logs:PutMetricFilter", "logs:DeleteLogGroup",
          "logs:DeleteSubscriptionFilter", "logs:PutRetentionPolicy",
          "sns:DeleteTopic", "sns:SetTopicAttributes", "sns:AddPermission", "sns:RemovePermission",
          "events:DeleteRule", "events:DisableRule", "events:PutRule", "events:RemoveTargets",
          "lambda:DeleteFunction", "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
          "guardduty:DeleteDetector", "guardduty:UpdateDetector", "guardduty:StopMonitoringMembers",
          "cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail", "cloudtrail:PutEventSelectors"
        ]
        Resource = "*"
        Condition = {
          ArnNotLike = { "aws:PrincipalArn" = var.detection_admin_principal_arns }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_organizations_policy_attachment" "scp_protect_detection_to_account" {
  policy_id = aws_organizations_policy.scp_protect_detection.id
  target_id = aws_organizations_account.workload.id
}

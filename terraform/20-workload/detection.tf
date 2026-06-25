# =====================================================================================
# Detect & Respond — CloudTrail (R11), GuardDuty (R11 + R12), SNS + CloudWatch alarms (R4).
#
# R12 ("role assumptions -> IP-based alerting") is satisfied by GuardDuty, NOT a bespoke
# Lambda. GuardDuty's managed findings already detect EC2 instance-role credentials being
# used away from the instance they were issued to:
#   * UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS
#       - IMDS-delivered role creds used from an IP OUTSIDE AWS (the source-IP case).
#   * UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.InsideAWS
#       - the same creds replayed from a DIFFERENT AWS account (which a naive allow-list of
#         AWS IP ranges would miss).
# Both are severity >= 4, so the GuardDuty -> EventBridge -> SNS rule at the bottom of this
# file already delivers them. We removed the hand-rolled EventBridge-on-AssumeRole + Lambda
# ("ith-ip-alerter") because it duplicated this managed coverage while adding an allow-list
# to maintain and a per-call Lambda to run. See controls/37-guardduty.md.
# =====================================================================================

# ---- SNS (all alerts land here) -----------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name              = "ith-security-alerts"
  kms_master_key_id = aws_kms_key.logs.arn
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "aws_iam_policy_document" "sns_policy" {
  statement {
    sid       = "AllowAccountManage"
    actions   = ["sns:Publish", "sns:Subscribe", "sns:GetTopicAttributes", "sns:SetTopicAttributes"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "AWS"
      identifiers = [local.root_arn]
    }
  }
  statement {
    sid       = "AllowServicePublishers"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.sns_policy.json
}

# ---- CloudTrail -> CloudWatch Logs --------------------------------------------------
resource "aws_cloudwatch_log_group" "trail" {
  name              = "/ith/cloudtrail"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.logs.arn
}

data "aws_iam_policy_document" "ct_to_logs_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ct_to_logs" {
  name               = "ith-cloudtrail-to-logs"
  assume_role_policy = data.aws_iam_policy_document.ct_to_logs_trust.json
}

resource "aws_iam_role_policy" "ct_to_logs" {
  name = "ith-cloudtrail-to-logs"
  role = aws_iam_role.ct_to_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "ith-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.logs.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.ct_to_logs.arn

  # Management events + S3 object-level (DATA) events on both buckets.
  #
  # Why data events matter (do NOT drop these to save cost):
  #   * A GetObject/PutObject 403 is a *data* event, not a management event. Without this
  #     selector, object-level reads and denials on the PHI bucket are not logged at all.
  #   * The `s3-access-denied` metric filter + alarm below silently DEPENDS on this. Remove
  #     data events and that alarm goes permanently blind: it never fires and looks healthy.
  #   * For PHI this is a HIPAA audit-trail requirement (45 CFR 164.312(b)), not optional.
  #   * Data events are OFF by default and billed per 100K events - scoped to these two
  #     bucket ARNs (not s3:::*) to keep cost bounded.
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.sensitive.arn}/", "${aws_s3_bucket.deident.arn}/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail, aws_iam_role_policy.ct_to_logs]
}

# ---- GuardDuty ----------------------------------------------------------------------
resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

# ---- CIS-style metric-filter alarms (R4: "alarms for everything") -------------------
locals {
  metric_filters = {
    root-usage = {
      pattern     = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
      description = "Root account used"
    }
    unauthorized-api = {
      pattern     = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"
      description = "Unauthorized / AccessDenied API calls"
    }
    console-no-mfa = {
      pattern     = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") }"
      description = "Console sign-in without MFA"
    }
    iam-policy-change = {
      pattern     = "{ ($.eventName = \"PutRolePolicy\") || ($.eventName = \"PutUserPolicy\") || ($.eventName = \"AttachRolePolicy\") || ($.eventName = \"DetachRolePolicy\") || ($.eventName = \"CreatePolicy\") || ($.eventName = \"DeletePolicy\") }"
      description = "IAM policy changes"
    }
    s3-policy-change = {
      pattern     = "{ ($.eventSource = \"s3.amazonaws.com\") && (($.eventName = \"PutBucketPolicy\") || ($.eventName = \"DeleteBucketPolicy\") || ($.eventName = \"PutBucketAcl\") || ($.eventName = \"PutBucketPublicAccessBlock\")) }"
      description = "S3 bucket policy / ACL / BPA changes"
    }
    kms-disable-delete = {
      pattern     = "{ ($.eventSource = \"kms.amazonaws.com\") && (($.eventName = \"DisableKey\") || ($.eventName = \"ScheduleKeyDeletion\")) }"
      description = "KMS key disabled or scheduled for deletion"
    }
    cloudtrail-change = {
      pattern     = "{ ($.eventName = \"StopLogging\") || ($.eventName = \"DeleteTrail\") || ($.eventName = \"UpdateTrail\") }"
      description = "CloudTrail tampering"
    }
    sg-change = {
      pattern     = "{ ($.eventName = \"AuthorizeSecurityGroupIngress\") || ($.eventName = \"RevokeSecurityGroupIngress\") || ($.eventName = \"CreateSecurityGroup\") || ($.eventName = \"DeleteSecurityGroup\") }"
      description = "Security group changes"
    }
    s3-access-denied = {
      # Only sees GetObject/PutObject denials because S3 DATA events are enabled in the
      # CloudTrail event_selector above. Disable data events and this alarm goes blind.
      # The alarm is count-only (dimensionless) - to learn who/what/how, query the
      # /ith/cloudtrail log group for the alarm window (userIdentity.arn, sourceIPAddress,
      # requestParameters.key).
      pattern     = "{ ($.eventSource = \"s3.amazonaws.com\") && ($.errorCode = \"AccessDenied\") }"
      description = "S3 AccessDenied (blocked read attempt on PHI)"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "f" {
  for_each       = local.metric_filters
  name           = "ith-${each.key}"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = each.value.pattern

  metric_transformation {
    name          = "ith-${each.key}"
    namespace     = "ITH/Security"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "a" {
  for_each            = local.metric_filters
  alarm_name          = "ith-${each.key}"
  alarm_description   = each.value.description
  namespace           = "ITH/Security"
  metric_name         = "ith-${each.key}"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# ---- R12: role-credential IP alerting is handled by GuardDuty (see header) -----------
# Intentionally NO custom EventBridge-on-AssumeRole rule / Lambda here. The
# InstanceCredentialExfiltration.OutsideAWS / .InsideAWS findings emitted by the GuardDuty
# detector below cover "EC2 role creds used off the instance" (by source IP and by account)
# and already flow to SNS via the sev>=4 GuardDuty rule. Documented in controls/37-guardduty.md.

# ---- [40] Change / CreateUser alerter : exclusion-based metric filters ---------------
# Alert on (a) IAM user creation and (b) ANY mutating action against this system's
# resources, UNLESS the actor is on the exclusion list (default: ITH-SuperAdmin + the
# deploy role). Implemented as CloudWatch Logs metric filters (not EventBridge) because
# CreateUser is a GLOBAL IAM event delivered to us-east-1 - an EventBridge rule in this
# region would miss it. The multi-region trail (include_global_service_events) writes all
# events into this one log group, so a filter here catches them regardless of region.
variable "change_alert_excluded_arns" {
  description = "Substrings of principal ARNs whose changes do NOT alert (the exclusion/allow list)."
  type        = list(string)
  default     = ["ITH-SuperAdmin", "OrganizationAccountAccessRole"] # super admin + IaC deploy role
}

locals {
  # Build '&& ($.userIdentity.arn != "*X*")' for each excluded principal substring.
  change_excl_clause = join(" ", [
    for a in var.change_alert_excluded_arns : "&& ($.userIdentity.arn != \"*${a}*\")"
  ])

  # [60] Detection self-protection — the detective half ("who watches the watchers").
  # The protect-detection SCP [60] (00-org) PREVENTS anyone but the deploy role from mutating
  # the detection stack; this metric filter DETECTS it if prevention is ever bypassed (e.g. a
  # break-glass actor coming through the mgmt account's OrganizationAccountAccessRole). The
  # exclusion here is deliberately NARROWER than change_excl_clause: only the IaC deploy role is
  # exempt (it legitimately Put/Delete-s these on every apply). We do NOT exempt SuperAdmin —
  # if anything but the pipeline touches the monitors we want to know, SCP block notwithstanding.
  detect_excl_arns = ["OrganizationAccountAccessRole"]
  detect_excl_clause = join(" ", [
    for a in local.detect_excl_arns : "&& ($.userIdentity.arn != \"*${a}*\")"
  ])
  detect_event_names = [
    "DeleteAlarms", "PutMetricAlarm", "DisableAlarmActions", "SetAlarmState", # CloudWatch alarms [35]
    "DeleteMetricFilter", "PutMetricFilter", "DeleteLogGroup",                # Logs / metric filters [34]
    "DeleteSubscriptionFilter", "PutRetentionPolicy",
    "DeleteTopic", "SetTopicAttributes", "RemovePermission",     # SNS topic [36]
    "DeleteRule", "DisableRule", "RemoveTargets",                # EventBridge rules (GuardDuty->SNS) [37]
    "DeleteDetector", "UpdateDetector", "StopMonitoringMembers", # GuardDuty [37]
  ]
  detect_event_clause = join(" || ", [
    for e in local.detect_event_names : "($.eventName = \"${e}\")"
  ])

  change_filters = {
    unauthorized-create-user = {
      pattern     = "{ ($.eventName = \"CreateUser\") ${local.change_excl_clause} }"
      description = "IAM user created by a non-excluded principal (exclusion: super admin + deploy role)"
    }
    unauthorized-change = {
      pattern     = "{ ($.readOnly IS FALSE) && ($.userIdentity.invokedBy NOT EXISTS) && ($.userIdentity.type != \"AWSService\") ${local.change_excl_clause} }"
      description = "Mutating action on a system resource by a non-excluded principal (exclusion: super admin + deploy role)"
    }
    detection-tampering = {
      pattern     = "{ (${local.detect_event_clause}) ${local.detect_excl_clause} }"
      description = "Detection stack (alarms / metric filters / log group / SNS / EventBridge / GuardDuty) modified by a non-deploy principal - backstops the protect-detection SCP [60]"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "change" {
  for_each       = local.change_filters
  name           = "ith-${each.key}"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = each.value.pattern

  metric_transformation {
    name          = "ith-${each.key}"
    namespace     = "ITH/Security"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "change" {
  for_each            = local.change_filters
  alarm_name          = "ith-${each.key}"
  alarm_description   = each.value.description
  namespace           = "ITH/Security"
  metric_name         = "ith-${each.key}"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ---- GuardDuty findings -> SNS ------------------------------------------------------
resource "aws_cloudwatch_event_rule" "guardduty" {
  name        = "ith-guardduty-findings"
  description = "High/medium GuardDuty findings"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail        = { severity = [{ numeric = [">=", 4] }] }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty.name
  target_id = "sns"
  arn       = aws_sns_topic.alerts.arn
}

# =====================================================================================
# Detect & Respond — CloudTrail (R11), GuardDuty (R11), SNS + CloudWatch alarms (R4),
# and the EventBridge -> Lambda AssumeRole IP alerter (R12).
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

  # management events + S3 object-level (data) events on both buckets
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
  alarm_description    = each.value.description
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

# ---- R12: AssumeRole IP alerter (EventBridge -> Lambda -> SNS) -----------------------
data "archive_file" "ip_alerter" {
  type        = "zip"
  source_file = "${path.module}/../../app/lambda-ip-alerter/index.py"
  output_path = "${path.module}/build/ip-alerter.zip"
}

data "aws_iam_policy_document" "ip_alerter_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ip_alerter" {
  name               = "ith-ip-alerter-role"
  assume_role_policy = data.aws_iam_policy_document.ip_alerter_trust.json
}

resource "aws_iam_role_policy_attachment" "ip_alerter_basic" {
  role       = aws_iam_role.ip_alerter.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ip_alerter" {
  name = "ith-ip-alerter-inline"
  role = aws_iam_role.ip_alerter.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.alerts.arn },
      { Effect = "Allow", Action = ["kms:GenerateDataKey*", "kms:Decrypt"], Resource = aws_kms_key.logs.arn }
    ]
  })
}

resource "aws_lambda_function" "ip_alerter" {
  function_name    = "ith-ip-alerter"
  role             = aws_iam_role.ip_alerter.arn
  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.ip_alerter.output_path
  source_code_hash = data.archive_file.ip_alerter.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      SNS_TOPIC     = aws_sns_topic.alerts.arn
      ALLOWED_CIDRS = join(",", var.allowed_assume_role_cidrs)
    }
  }
}

resource "aws_cloudwatch_event_rule" "assume_role" {
  name        = "ith-assume-role-ip"
  description = "Fire on sts:AssumeRole* for IP-based alerting"
  event_pattern = jsonencode({
    source        = ["aws.sts"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["AssumeRole", "AssumeRoleWithSAML", "AssumeRoleWithWebIdentity"]
    }
  })
}

resource "aws_cloudwatch_event_target" "assume_role" {
  rule      = aws_cloudwatch_event_rule.assume_role.name
  target_id = "ip-alerter"
  arn       = aws_lambda_function.ip_alerter.arn
}

resource "aws_lambda_permission" "assume_role_events" {
  statement_id  = "AllowEventBridgeAssumeRole"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ip_alerter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.assume_role.arn
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

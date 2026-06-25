# =====================================================================================
# S3 — two data buckets (R7 account-id suffix naming) + the CloudTrail log bucket.
#   phi-sensitive-<acct> : full (tokenized) ePHI, reachable ONLY from inside the VPC
#                          (aws:sourceVpce) OR via the Object Lambda access point (P1).
#                          A human/laptop with no vpce is DENIED -> must use the EC2 UI (C1).
#   phi-deident-<acct>   : de-identified copy, readable anywhere IN THE ORG (C4), still
#                          TLS-only + KMS + org-locked.
# Org-only access (R9) is primarily enforced by the RCP; repeated here as belt-and-braces.
# =====================================================================================

# -------------------------------------------------------------------------------------
# Sensitive bucket
# -------------------------------------------------------------------------------------
resource "aws_s3_bucket" "sensitive" {
  bucket = local.sensitive_bucket
  tags   = { Name = local.sensitive_bucket, DataClass = "phi-sensitive" }
}

resource "aws_s3_bucket_public_access_block" "sensitive" {
  bucket                  = aws_s3_bucket.sensitive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sensitive" {
  # Per-object encryption uses the PER-PATIENT CMK (set explicitly on upload, R15).
  # This default is the SSE-KMS safety net; bucket key lowers KMS call cost.
  bucket = aws_s3_bucket.sensitive.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "sensitive_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [aws_s3_bucket.sensitive.arn, "${aws_s3_bucket.sensitive.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid     = "DenyOutsideOrg"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [aws_s3_bucket.sensitive.arn, "${aws_s3_bucket.sensitive.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEqualsIfExists"
      variable = "aws:PrincipalOrgID"
      values   = [local.org_id]
    }
    condition {
      test     = "BoolIfExists"
      variable = "aws:PrincipalIsAWSService"
      values   = ["false"]
    }
  }

  # The core control: reads must come from inside the VPC (sourceVpce) OR via our
  # access point. Anything else (a human laptop) is denied -> EC2 UI only (C1).
  # EXEMPTION: the OrganizationAccountAccessRole is the infra/break-glass MANAGEMENT
  # principal (how Terraform manages the bucket). It is exempted so refresh/import work
  # from outside the VPC; the 3 IdP admin identities are NOT this role, so they remain
  # fully VPC-gated and must still use the EC2 UI.
  statement {
    sid     = "DenyReadsNotFromVpcOrAccessPoint"
    effect  = "Deny"
    actions = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"]
    resources = [aws_s3_bucket.sensitive.arn, "${aws_s3_bucket.sensitive.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:sourceVpce"
      values   = [aws_vpc_endpoint.s3_gw.id, aws_vpc_endpoint.s3_interface.id]
    }
    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:DataAccessPointAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "BoolIfExists"
      variable = "aws:PrincipalIsAWSService"
      values   = ["false"]
    }
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/OrganizationAccountAccessRole"]
    }
  }

  # Delegate to same-account access points (lets the Object Lambda access point read, P1).
  statement {
    sid     = "AllowSameAccountAccessPointDelegation"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"]
    resources = [aws_s3_bucket.sensitive.arn, "${aws_s3_bucket.sensitive.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:DataAccessPointAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id
  policy = data.aws_iam_policy_document.sensitive_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.sensitive]
}

# -------------------------------------------------------------------------------------
# De-identified bucket (bucket 2) — readable org-wide, still org-locked + TLS + KMS
# -------------------------------------------------------------------------------------
resource "aws_s3_bucket" "deident" {
  bucket = local.deident_bucket
  tags   = { Name = local.deident_bucket, DataClass = "phi-deidentified" }
}

resource "aws_s3_bucket_public_access_block" "deident" {
  bucket                  = aws_s3_bucket.deident.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "deident" {
  bucket = aws_s3_bucket.deident.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deident" {
  bucket = aws_s3_bucket.deident.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.deident.arn
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "deident_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.deident.arn, "${aws_s3_bucket.deident.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
  statement {
    sid       = "DenyOutsideOrg"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.deident.arn, "${aws_s3_bucket.deident.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEqualsIfExists"
      variable = "aws:PrincipalOrgID"
      values   = [local.org_id]
    }
    condition {
      test     = "BoolIfExists"
      variable = "aws:PrincipalIsAWSService"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "deident" {
  bucket     = aws_s3_bucket.deident.id
  policy     = data.aws_iam_policy_document.deident_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.deident]
}

# -------------------------------------------------------------------------------------
# CloudTrail log bucket
# -------------------------------------------------------------------------------------
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = local.cloudtrail_bucket
  force_destroy = true # logs; allow teardown
  tags          = { Name = local.cloudtrail_bucket }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${local.region}:${local.account_id}:trail/ith-trail"]
    }
  }
  statement {
    sid       = "AWSCloudTrailWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${local.region}:${local.account_id}:trail/ith-trail"]
    }
  }
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.cloudtrail.arn, "${aws_s3_bucket.cloudtrail.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket     = aws_s3_bucket.cloudtrail.id
  policy     = data.aws_iam_policy_document.cloudtrail_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# =====================================================================================
# IAM — the four data-plane principals (one per access path) + their least-privilege.
#   ec2_app        P3  EC2 web app (human read UI), SSM-managed, no SSH
#   lambda_redactor P1 Object Lambda redactor ("basic reader", returns non-sensitive)
#   s3_reader      P4  the "s3" user — direct S3 read, gated to in-VPC by bucket policy
#   onprem_k8s     P2  on-prem k8s node, reaches S3 across VPC peering
#
# KMS perms use a wildcard *resource* (account key namespace) on purpose: the per-patient
# KMS *key policy* (kms.tf) is the authoritative grant, so there is no kms<->iam cycle.
# =====================================================================================

locals {
  kms_key_namespace = "arn:${data.aws_partition.current.partition}:kms:${local.region}:${local.account_id}:key/*"

  reader_role_arns = [
    aws_iam_role.ec2_app.arn,
    aws_iam_role.lambda_redactor.arn,
    aws_iam_role.s3_reader.arn,
    aws_iam_role.onprem_k8s.arn,
  ]
}

# ---- assume-role trust documents ----------------------------------------------------
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "s3reader_trust" {
  # The "s3" user path. Assumable by in-account principals that hold sts:AssumeRole
  # (e.g. the EC2 web host, for the in-VPC P4 demo). In a full Entra deploy this maps to
  # the AWSReservedSSO ITH-S3Reader role.
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"]
    }
  }
}

# =====================================================================================
# P3 — EC2 web app role (the sole human read path). SSM-only access (no SSH/keypair).
# =====================================================================================
resource "aws_iam_role" "ec2_app" {
  name               = "ith-ec2-webapp-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "ec2_app_ssm" {
  role       = aws_iam_role.ec2_app.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ec2_app" {
  statement {
    sid       = "ReadBuckets"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.sensitive.arn, "${aws_s3_bucket.sensitive.arn}/*", aws_s3_bucket.deident.arn, "${aws_s3_bucket.deident.arn}/*"]
  }
  statement {
    sid       = "DecryptPhi"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [local.kms_key_namespace]
  }
  statement {
    sid       = "AssumeS3ReaderForP4Demo"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.s3_reader.arn]
  }
}

resource "aws_iam_role_policy" "ec2_app" {
  name   = "ith-ec2-webapp-inline"
  role   = aws_iam_role.ec2_app.id
  policy = data.aws_iam_policy_document.ec2_app.json
}

resource "aws_iam_instance_profile" "ec2_app" {
  name = "ith-ec2-webapp-profile"
  role = aws_iam_role.ec2_app.name
}

# =====================================================================================
# P1 — Object Lambda redactor role ("basic reader"; returns de-identified fields only)
# =====================================================================================
resource "aws_iam_role" "lambda_redactor" {
  name               = "ith-lambda-redactor-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_redactor.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_redactor" {
  statement {
    sid     = "ReadSensitiveViaAccessPoint"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.sensitive.arn}/*",
      "${aws_s3_access_point.sensitive.arn}/object/*",
    ]
  }
  statement {
    sid       = "DecryptPhi"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [local.kms_key_namespace]
  }
}

resource "aws_iam_role_policy" "lambda_redactor" {
  name   = "ith-lambda-redactor-inline"
  role   = aws_iam_role.lambda_redactor.id
  policy = data.aws_iam_policy_document.lambda_redactor.json
}

# =====================================================================================
# P4 — the "s3" user role: can GetObject, but the BUCKET POLICY denies unless in-VPC.
# =====================================================================================
resource "aws_iam_role" "s3_reader" {
  name               = "ith-s3-reader-role"
  assume_role_policy = data.aws_iam_policy_document.s3reader_trust.json
}

data "aws_iam_policy_document" "s3_reader" {
  statement {
    sid       = "ReadSensitive"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.sensitive.arn, "${aws_s3_bucket.sensitive.arn}/*"]
  }
  statement {
    sid       = "DecryptPhi"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [local.kms_key_namespace]
  }
}

resource "aws_iam_role_policy" "s3_reader" {
  name   = "ith-s3-reader-inline"
  role   = aws_iam_role.s3_reader.id
  policy = data.aws_iam_policy_document.s3_reader.json
}

# =====================================================================================
# P2 — on-prem k8s node role (instance role on the "on-prem" EC2; reads S3 over peering)
# =====================================================================================
resource "aws_iam_role" "onprem_k8s" {
  name               = "ith-onprem-k8s-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "onprem_ssm" {
  role       = aws_iam_role.onprem_k8s.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "onprem_k8s" {
  statement {
    sid       = "ReadSensitive"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.sensitive.arn, "${aws_s3_bucket.sensitive.arn}/*"]
  }
  # P5 — the enclave pod WRITES client-side-encrypted blobs under enclave/* only.
  statement {
    sid       = "WriteEnclaveBlobs"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.sensitive.arn}/enclave/*"]
  }
  # kms:Decrypt covers the per-patient CMKs (P2 read). GenerateDataKey is added for the
  # P5 envelope. The IAM grant is broad on the key namespace ON PURPOSE — the enclave KMS
  # key's OWN policy [43] is the authoritative gate (attestation/PCR0), so a non-attested
  # call from this role is still denied by the key policy.
  statement {
    sid       = "DecryptPhi"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = [local.kms_key_namespace]
  }
  # P5 — publish the measured PCR0 to SSM so the 2nd apply can lock the key to it.
  statement {
    sid       = "PublishEnclavePcr0"
    actions   = ["ssm:PutParameter", "ssm:GetParameter"]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${local.region}:${local.account_id}:parameter${local.enclave_pcr0_param}"]
  }
}

resource "aws_iam_role_policy" "onprem_k8s" {
  name   = "ith-onprem-k8s-inline"
  role   = aws_iam_role.onprem_k8s.id
  policy = data.aws_iam_policy_document.onprem_k8s.json
}

resource "aws_iam_instance_profile" "onprem_k8s" {
  name = "ith-onprem-k8s-profile"
  role = aws_iam_role.onprem_k8s.name
}

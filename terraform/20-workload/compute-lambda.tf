# =====================================================================================
# P1 — the Lambda "basic reader" (C2). Intended design = S3 Object Lambda Access Point,
# but AWS gates S3 Object Lambda to existing customers (a new account gets AccessDenied on
# create — see docs/data-plane-paths.md). Supported equivalent: a standard S3 ACCESS POINT
# + a Lambda (IAM-auth Function URL) that reads THROUGH the access point and returns only
# non-sensitive fields. The bucket policy delegates to same-account access points, so the
# VPC-lock is satisfied via the access-point path while raw PHI never leaves the Lambda.
# =====================================================================================

# Standard S3 access point on the sensitive bucket (the redactor reads through this).
resource "aws_s3_access_point" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id
  name   = "ith-sensitive-ap"
}

data "archive_file" "redactor" {
  type        = "zip"
  source_file = "${path.module}/../../app/lambda-redactor/index.py"
  output_path = "${path.module}/build/redactor.zip"
}

resource "aws_lambda_function" "redactor" {
  function_name    = "ith-redactor"
  role             = aws_iam_role.lambda_redactor.arn
  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.redactor.output_path
  source_code_hash = data.archive_file.redactor.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = { AP_ARN = aws_s3_access_point.sensitive.arn }
  }

  tags = { Name = "ith-redactor" }
}

# IAM-authenticated Function URL = the "access point" the basic reader calls.
resource "aws_lambda_function_url" "redactor" {
  function_name      = aws_lambda_function.redactor.function_name
  authorization_type = "AWS_IAM"
}

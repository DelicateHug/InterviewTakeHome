# =====================================================================================
# P1 — the Lambda "basic reader": an S3 OBJECT LAMBDA ACCESS POINT whose Lambda strips
# all identifiers and returns only non-sensitive fields (C2). The Lambda runs OUTSIDE the
# VPC and reads the bucket through the supporting access point (the bucket policy delegates
# to same-account access points), so the VPC-lock on the bucket is not in its way.
# =====================================================================================

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

  tags = { Name = "ith-redactor" }
}

# Supporting (standard) access point on the sensitive bucket.
resource "aws_s3_access_point" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id
  name   = "ith-sensitive-ap"
}

# Object Lambda access point that invokes the redactor on GetObject.
resource "aws_s3control_object_lambda_access_point" "redactor" {
  name = "ith-redactor-olap"

  configuration {
    supporting_access_point = aws_s3_access_point.sensitive.arn

    transformation_configuration {
      actions = ["GetObject"]
      content_transformation {
        aws_lambda {
          function_arn = aws_lambda_function.redactor.arn
        }
      }
    }
  }
}

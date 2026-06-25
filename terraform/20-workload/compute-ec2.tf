# =====================================================================================
# P3 — EC2 web app: the SOLE human read path. SSM-only (no key pair, no SSH, no public IP).
# Reached via `aws ssm start-session ... AWS-StartPortForwardingSession` to :8080.
# =====================================================================================

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  patient_object_keys = [for p in local.patient_index.patients : "patients/${p.patient_id}.json"]
  first_patient_key   = "patients/${local.patient_index.patients[0].patient_id}.json"
}

resource "aws_instance" "webapp" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.workload_a.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_app.name
  associate_public_ip_address = false
  # NO key_name on purpose -> there is no SSH key; access is SSM Session Manager only.

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_size = 8
  }

  user_data_base64 = base64encode(templatefile("${path.module}/templates/webapp_userdata.sh.tftpl", {
    server_py_b64 = base64encode(file("${path.module}/../../app/webapp/server.py"))
    bucket        = aws_s3_bucket.sensitive.id
    region        = local.region
    keys          = join(",", local.patient_object_keys)
  }))

  tags = { Name = "ith-webapp" }

  # Don't let AL2023 AMI churn (most_recent) force surprise replacements.
  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [
    aws_vpc_endpoint.interface, # SSM endpoints must exist for the agent to register
    aws_vpc_endpoint.s3_gw,     # S3 reachable privately
  ]
}

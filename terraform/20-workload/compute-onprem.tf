# =====================================================================================
# P2/P5 — "on-prem" Kubernetes node (single-node k3s) in the peered VPC.
#
#  P2 (unchanged): a CronJob reads the sensitive bucket ACROSS THE PEERING via the
#                  workload S3 interface endpoint (network-gated by aws:sourceVpce).
#  P5 (added):     the node is enclave-capable. A k8s pod reads AND WRITES the bucket,
#                  but the crypto is gated by a Nitro Enclave: the enclave KMS key
#                  alias/ith/enclave [43] only unlocks for the measured enclave image
#                  (kms:RecipientAttestation:PCR0). See app/enclave/ and controls/42-44.
#
# SSM-managed (no SSH). hop_limit=2 so in-cluster pods can reach IMDS for the node role.
# c6i.xlarge + enclave_options because Nitro Enclaves are NOT supported on t3.
# =====================================================================================

# P5 app assets are bundled into one deflate-compressed zip and shipped in user_data
# (the raw files exceed the 16KB user_data limit). The node extracts it with python3.
data "archive_file" "enclave_assets" {
  type        = "zip"
  output_path = "${path.module}/builds/enclave-assets.zip"

  source {
    content  = file("${path.module}/../../app/enclave/Dockerfile")
    filename = "Dockerfile"
  }
  source {
    content  = file("${path.module}/../../app/enclave/enclave_server.py")
    filename = "enclave_server.py"
  }
  source {
    content  = file("${path.module}/../../app/enclave/host_broker.py")
    filename = "host_broker.py"
  }
  source {
    content  = file("${path.module}/../../app/enclave/build-enclave.sh")
    filename = "build-enclave.sh"
  }
  source {
    content  = file("${path.module}/../../app/enclave/setup-node.sh")
    filename = "setup-node.sh"
  }
  source {
    content  = file("${path.module}/../../app/onprem/phi-rw-enclave.yaml")
    filename = "phi-rw-enclave.yaml"
  }
}

resource "aws_instance" "onprem" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.enclave_instance_type
  subnet_id                   = aws_subnet.onprem_a.id
  vpc_security_group_ids      = [aws_security_group.onprem_node.id]
  iam_instance_profile        = aws_iam_instance_profile.onprem_k8s.name
  associate_public_ip_address = true # datacenter egress for k3s installer + enclave->KMS via vsock-proxy

  # P5 — run a Nitro Enclave on this instance (needs an enclave-capable Nitro type).
  enclave_options {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # pods -> IMDS -> node role
  }

  root_block_device {
    encrypted   = true
    volume_size = 30 # docker + SDK build + EIF
  }

  user_data_base64 = base64encode(templatefile("${path.module}/templates/onprem_userdata.sh.tftpl", {
    bucket = aws_s3_bucket.sensitive.id
    region = local.region
    # dns_entry is a wildcard "*.vpce-...". The S3 interface-endpoint TLS cert covers
    # "bucket.vpce-..." (and "*.bucket.vpce-..."), so use the "bucket." infix form; aws
    # cli then virtual-hosts to "<bucket>.bucket.vpce-..." which matches the cert.
    s3_vpce_dns = replace(aws_vpc_endpoint.s3_interface.dns_entry[0].dns_name, "*.", "bucket.")
    sample_key  = local.first_patient_key

    # ---- P5 enclave wiring ----
    account_id        = local.account_id
    enclave_key_alias = aws_kms_alias.enclave.name
    pcr0_param        = local.enclave_pcr0_param
    # All app assets as one deflate-compressed zip (extracted on the node with python3).
    assets_zip_b64 = filebase64(data.archive_file.enclave_assets.output_path)
  }))
  user_data_replace_on_change = true # re-provision k3s + enclave when the boot script changes

  tags = { Name = "ith-onprem-k8s" }

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [
    aws_route.onprem_to_workload,
    aws_route.workload_to_onprem,
    aws_vpc_endpoint.s3_interface,
  ]
}

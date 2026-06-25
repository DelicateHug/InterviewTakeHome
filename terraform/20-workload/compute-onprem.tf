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
    # App assets are shipped inline (base64) and unpacked on the node, mirroring the
    # webapp pattern. The node builds the EIF from these, captures PCR0, and runs it.
    dockerfile_b64     = base64encode(file("${path.module}/../../app/enclave/Dockerfile"))
    enclave_server_b64 = base64encode(file("${path.module}/../../app/enclave/enclave_server.py"))
    host_broker_b64    = base64encode(file("${path.module}/../../app/enclave/host_broker.py"))
    build_enclave_b64  = base64encode(file("${path.module}/../../app/enclave/build-enclave.sh"))
    setup_node_b64     = base64encode(file("${path.module}/../../app/enclave/setup-node.sh"))
    pod_manifest_b64   = base64encode(file("${path.module}/../../app/onprem/phi-rw-enclave.yaml"))
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

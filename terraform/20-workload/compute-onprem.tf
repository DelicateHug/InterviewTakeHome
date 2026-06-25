# =====================================================================================
# P2 — "on-prem" Kubernetes node (single-node k3s) in the peered VPC. A CronJob reads the
# sensitive bucket ACROSS THE PEERING via the workload S3 interface endpoint. SSM-managed
# (no SSH). hop_limit=2 so in-cluster pods can reach IMDS for the node instance role.
# =====================================================================================

resource "aws_instance" "onprem" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.onprem_a.id
  vpc_security_group_ids      = [aws_security_group.onprem_node.id]
  iam_instance_profile        = aws_iam_instance_profile.onprem_k8s.name
  associate_public_ip_address = true # datacenter egress for the k3s installer

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # pods -> IMDS -> node role
  }

  root_block_device {
    encrypted   = true
    volume_size = 20
  }

  user_data_base64 = base64encode(templatefile("${path.module}/templates/onprem_userdata.sh.tftpl", {
    bucket      = aws_s3_bucket.sensitive.id
    region      = local.region
    # dns_entry is a wildcard "*.vpce-...". The S3 interface-endpoint TLS cert covers
    # "bucket.vpce-..." (and "*.bucket.vpce-..."), so use the "bucket." infix form; aws
    # cli then virtual-hosts to "<bucket>.bucket.vpce-..." which matches the cert.
    s3_vpce_dns = replace(aws_vpc_endpoint.s3_interface.dns_entry[0].dns_name, "*.", "bucket.")
    sample_key  = local.first_patient_key
  }))
  user_data_replace_on_change = true # re-provision k3s when the boot script changes

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

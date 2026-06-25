# =====================================================================================
# Network — workload VPC (NO internet) + "on-prem" VPC, joined by VPC PEERING (P2).
# S3 reached privately via a GATEWAY endpoint (in-VPC) and an INTERFACE endpoint
# (so the peered on-prem VPC can reach S3 over the peering). SSM uses interface endpoints
# so the workload VPC needs no IGW/NAT at all.
#
# Peering scalability caveat (docs/data-plane-paths.md): peering is non-transitive & N²;
# Transit Gateway is the scalable successor. Used here to match the brief.
# =====================================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  workload_cidr = "10.20.0.0/16"
  onprem_cidr   = "192.168.0.0/16"
  az_a          = data.aws_availability_zones.available.names[0]
  az_b          = data.aws_availability_zones.available.names[1]
}

# ---- Workload VPC (private only) ----------------------------------------------------
resource "aws_vpc" "workload" {
  cidr_block           = local.workload_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "ith-workload-vpc" }
}

resource "aws_subnet" "workload_a" {
  vpc_id            = aws_vpc.workload.id
  cidr_block        = "10.20.1.0/24"
  availability_zone = local.az_a
  tags              = { Name = "ith-workload-private-a" }
}

resource "aws_subnet" "workload_b" {
  vpc_id            = aws_vpc.workload.id
  cidr_block        = "10.20.2.0/24"
  availability_zone = local.az_b
  tags              = { Name = "ith-workload-private-b" }
}

resource "aws_route_table" "workload" {
  vpc_id = aws_vpc.workload.id
  tags   = { Name = "ith-workload-private-rt" }
}

resource "aws_route_table_association" "workload_a" {
  subnet_id      = aws_subnet.workload_a.id
  route_table_id = aws_route_table.workload.id
}

resource "aws_route_table_association" "workload_b" {
  subnet_id      = aws_subnet.workload_b.id
  route_table_id = aws_route_table.workload.id
}

# ---- "On-prem" VPC (has an IGW for egress — represents a datacenter perimeter) -------
resource "aws_vpc" "onprem" {
  cidr_block           = local.onprem_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "ith-onprem-vpc" }
}

resource "aws_subnet" "onprem_a" {
  vpc_id                  = aws_vpc.onprem.id
  cidr_block              = "192.168.1.0/24"
  availability_zone       = local.az_a
  map_public_ip_on_launch = true
  tags                    = { Name = "ith-onprem-subnet-a" }
}

resource "aws_internet_gateway" "onprem" {
  vpc_id = aws_vpc.onprem.id
  tags   = { Name = "ith-onprem-igw" }
}

resource "aws_route_table" "onprem" {
  vpc_id = aws_vpc.onprem.id
  tags   = { Name = "ith-onprem-rt" }
}

resource "aws_route" "onprem_internet" {
  route_table_id         = aws_route_table.onprem.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.onprem.id
}

resource "aws_route_table_association" "onprem_a" {
  subnet_id      = aws_subnet.onprem_a.id
  route_table_id = aws_route_table.onprem.id
}

# ---- VPC peering (P2) ---------------------------------------------------------------
resource "aws_vpc_peering_connection" "workload_onprem" {
  vpc_id      = aws_vpc.onprem.id
  peer_vpc_id = aws_vpc.workload.id
  auto_accept = true
  tags        = { Name = "ith-onprem-to-workload" }
}

resource "aws_route" "workload_to_onprem" {
  route_table_id            = aws_route_table.workload.id
  destination_cidr_block    = local.onprem_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.workload_onprem.id
}

resource "aws_route" "onprem_to_workload" {
  route_table_id            = aws_route_table.onprem.id
  destination_cidr_block    = local.workload_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.workload_onprem.id
}

# ---- S3 GATEWAY endpoint (in-VPC clients: EC2 web app, redactor-in-VPC) --------------
resource "aws_vpc_endpoint" "s3_gw" {
  vpc_id            = aws_vpc.workload.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.workload.id]
  tags              = { Name = "ith-s3-gateway-vpce" }
}

# ---- Interface endpoints (SSM + STS + KMS + Logs) so workload VPC needs no internet --
locals {
  interface_services = [
    "ssm", "ssmmessages", "ec2messages", # SSM Session Manager (no SSH)
    "sts", "kms", "logs",                # assume-role, KMS, CloudWatch logs
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(local.interface_services)
  vpc_id              = aws_vpc.workload.id
  service_name        = "com.amazonaws.${local.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.workload_a.id, aws_subnet.workload_b.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = { Name = "ith-vpce-${each.value}" }
}

# ---- S3 INTERFACE endpoint (reachable across peering by the on-prem node, P2) --------
# private_dns disabled so it doesn't shadow the gateway endpoint for in-VPC clients;
# the on-prem node targets it via its vpce-specific regional DNS name.
resource "aws_vpc_endpoint" "s3_interface" {
  vpc_id              = aws_vpc.workload.id
  service_name        = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.workload_a.id, aws_subnet.workload_b.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = false
  tags                = { Name = "ith-s3-interface-vpce" }
}

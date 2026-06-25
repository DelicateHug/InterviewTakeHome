# =====================================================================================
# R17 — Security groups use SECURITY-GROUP-AS-SOURCE (not CIDR) on specific ports.
#   endpoints SG  <= app SG            : 443   (in-VPC)
#   endpoints SG  <= onprem-node SG    : 443   (CROSS-VPC ref over the peering)
#   app SG        : no inbound (reached only via SSM Session Manager port-forward)
# Egress is scoped to the endpoints SG / the S3 gateway prefix list, not 0.0.0.0/0.
# =====================================================================================

# ---- Interface-endpoint SG (the "allow" target) -------------------------------------
resource "aws_security_group" "endpoints" {
  name        = "ith-endpoints-sg"
  description = "Interface VPC endpoints — 443 from app SG and on-prem node SG only"
  vpc_id      = aws_vpc.workload.id
  tags        = { Name = "ith-endpoints-sg" }
}

# ---- Web-app SG (P3) : no inbound; egress only to endpoints + S3 prefix list ---------
resource "aws_security_group" "app" {
  name        = "ith-app-sg"
  description = "EC2 web app — no inbound (SSM only); egress 443 to endpoints + S3"
  vpc_id      = aws_vpc.workload.id
  tags        = { Name = "ith-app-sg" }
}

# ---- On-prem node SG (P2) : no inbound (SSM only); egress all (internet + S3 vpce) ---
resource "aws_security_group" "onprem_node" {
  name        = "ith-onprem-node-sg"
  description = "On-prem k8s node — no inbound (SSM only); egress to internet + S3 vpce"
  vpc_id      = aws_vpc.onprem.id
  tags        = { Name = "ith-onprem-node-sg" }
}

# ---- SG-as-source ingress rules (the heart of R17) ----------------------------------
resource "aws_vpc_security_group_ingress_rule" "endpoints_from_app" {
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = aws_security_group.app.id # SG as source, not CIDR
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "HTTPS from the web-app SG"
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_onprem" {
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = aws_security_group.onprem_node.id # cross-VPC over peering
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "HTTPS from the on-prem node SG (peered)"
}

# ---- Egress rules (scoped) ----------------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "app_to_endpoints" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "HTTPS to interface endpoints (SSM/STS/KMS/Logs)"
}

resource "aws_vpc_security_group_egress_rule" "app_to_s3" {
  security_group_id = aws_security_group.app.id
  prefix_list_id    = aws_vpc_endpoint.s3_gw.prefix_list_id # S3 gateway endpoint
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS to S3 via the gateway endpoint"
}

resource "aws_vpc_security_group_egress_rule" "endpoints_self_response" {
  # endpoints SG needs no special egress; allow 443 back within VPC for completeness.
  security_group_id = aws_security_group.endpoints.id
  cidr_ipv4         = local.workload_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS responses within the workload VPC"
}

resource "aws_vpc_security_group_egress_rule" "onprem_all" {
  security_group_id = aws_security_group.onprem_node.id
  cidr_ipv4         = "0.0.0.0/0" # on-prem datacenter egress (k3s install + S3 vpce)
  ip_protocol       = "-1"
  description       = "On-prem node egress (internet for k3s; S3 via peered vpce)"
}

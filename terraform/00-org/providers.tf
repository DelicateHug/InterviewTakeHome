# Runs against the ORG MANAGEMENT account (337066574719).
# Organizations is a global service; the region is only for the provider session.
provider "aws" {
  profile = var.aws_profile
  region  = var.region

  default_tags {
    tags = local.tags
  }
}

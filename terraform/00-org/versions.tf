terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.74.0" # RCP (RESOURCE_CONTROL_POLICY) support
    }
  }
}

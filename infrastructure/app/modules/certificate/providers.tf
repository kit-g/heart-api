# Named so a caller can hand in a us-east-1 configuration for CloudFront's
# certificates. Source only: versions are pinned by each environment.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

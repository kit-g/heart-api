terraform {
  required_version = ">= 1.14.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.40.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "2.7.1"
    }
  }
}

provider "aws" {
  default_tags {
    tags = var.tags
  }
}


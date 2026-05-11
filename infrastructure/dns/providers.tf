terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.40.0"
    }
  }
}

provider "aws" {
  region  = "ca-central-1"
  profile = "heart-dev"
}

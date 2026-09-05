terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.40.0"
    }

    # Used by ../../stack/firebase.tf; pinned here (not in the module) so
    # Dependabot bumps each environment separately.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.0"
    }
  }
}

provider "aws" {
  region  = "ca-central-1"
  profile = "heart-dev"
}

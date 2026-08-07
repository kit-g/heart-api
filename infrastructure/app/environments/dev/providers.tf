terraform {
  required_version = ">= 1.14.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.40.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "2.8.0"
    }

    supabase = {
      source  = "supabase/supabase"
      version = "1.10.1"
    }
  }
}

provider "aws" {
  default_tags {
    tags = var.tags
  }
}

data "aws_s3_object" "supabase_creds" {
  bucket = module.content.static_bucket.bucket
  key    = "secrets/supabase.json"
}

provider "supabase" {
  access_token = jsondecode(data.aws_s3_object.supabase_creds.body).api_token
}


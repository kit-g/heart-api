terraform {
  required_providers {
    supabase = {
      source  = "supabase/supabase"
      version = "~> 1.9.0"
    }
  }
}

resource "aws_s3_bucket" "content" {
  bucket = "${var.account_id}-${var.region}-content"
}

resource "aws_s3_bucket" "static" {
  bucket = "${var.account_id}-${var.region}-static"
}

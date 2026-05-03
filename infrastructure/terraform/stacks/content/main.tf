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

resource "aws_s3_bucket_lifecycle_configuration" "delete_raw_uploads" {
  bucket = aws_s3_bucket.content.id

  rule {
    id     = "expire-uploads"
    status = "Enabled"

    filter { prefix = "uploads/" }

    expiration { days = 1 }
  }
}

resource "aws_s3_bucket" "static" {
  bucket = "${var.account_id}-${var.region}-static"
}

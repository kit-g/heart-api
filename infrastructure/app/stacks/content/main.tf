terraform {
  required_providers {
    supabase = {
      source  = "supabase/supabase"
      # Minimum only, on purpose: the environment roots pin the exact version
      # (and Dependabot bumps those pins). An upper bound here would conflict
      # with every such bump — as `~> 1.9.0` vs the roots' 1.10.1 once did.
      version = ">= 1.9.0"
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

  # Raw exercise GIFs are redundant once the assets Lambda has copied them to
  # exercises/<name>/. Keep them a week — long enough to re-fire the pipeline
  # (e.g. after a bad deploy) before they auto-clean.
  rule {
    id     = "expire-exercise-uploads"
    status = "Enabled"

    filter {
      prefix = "exercise-uploads/"
    }

    expiration {
      days = 7
    }
  }
}

resource "aws_s3_bucket" "static" {
  bucket = "${var.account_id}-${var.region}-static"
}

resource "aws_s3_bucket_notification" "content_events" {
  bucket      = aws_s3_bucket.content.id
  eventbridge = true
}

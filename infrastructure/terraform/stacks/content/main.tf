resource "aws_s3_bucket" "content" {
  bucket = "${var.account_id}-${var.region}-content"
}

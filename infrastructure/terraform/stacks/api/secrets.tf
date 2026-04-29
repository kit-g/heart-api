data "aws_s3_object" "rds_secret" {
  bucket = var.static_bucket.bucket
  key    = "secrets/rds.json"
}

locals {
  rds_creds = jsondecode(data.aws_s3_object.rds_secret.body)
}

data "aws_s3_object" "supabase_secret" {
  bucket = aws_s3_bucket.static.bucket
  key    = "secrets/supabase.json"
}

locals {
  supabase_creds = jsondecode(data.aws_s3_object.supabase_secret.body)
}


resource "supabase_project" "heart" {
  name              = var.supabase_project.name
  organization_id   = local.supabase_creds.org_id
  database_password = local.supabase_creds.password
  region            = local.supabase_creds.region

  lifecycle {
    ignore_changes = [
      database_password,
      instance_size,
    ]
  }
}

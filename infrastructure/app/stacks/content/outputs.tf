output "content_bucket" {
  value = aws_s3_bucket.content
}

output "static_bucket" {
  value = aws_s3_bucket.static
}

locals {
  pooler_port   = 5432
  database_name = "heart"
}

output "database" {
  value = {
    id              = supabase_project.heart.id
    name            = supabase_project.heart.name
    region          = local.supabase_creds.region
    organization_id = supabase_project.heart.organization_id
    password        = local.supabase_creds.password
    connection      = "postgres://postgres.${supabase_project.heart.id}:${local.supabase_creds.password}@aws-0-${local.supabase_creds.region}.pooler.supabase.com:6543/${local.database_name}"
    host            = "aws-1-${local.supabase_creds.region}.pooler.supabase.com"
    user            = "postgres.${supabase_project.heart.id}"
    port            = local.pooler_port
    database        = local.database_name
  }
}

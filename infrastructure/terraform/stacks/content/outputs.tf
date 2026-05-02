output "content_bucket" {
  value = aws_s3_bucket.content
}

output "static_bucket" {
  value = aws_s3_bucket.static
}

locals {
  pooler_port   = 6543
  database_name = "postgres"
}

output "database" {
  value = {
    id              = supabase_project.heart.id
    name            = supabase_project.heart.name
    region          = supabase_project.heart.region
    organization_id = supabase_project.heart.organization_id
    password        = supabase_project.heart.database_password
    connection      = "postgres://postgres.${supabase_project.heart.id}:${supabase_project.heart.database_password}@aws-0-${supabase_project.heart.region}.pooler.supabase.com:6543/${local.database_name}"
    host            = "aws-1-${supabase_project.heart.region}.pooler.supabase.com"
    user            = "postgres.${supabase_project.heart.id}"
    port            = local.pooler_port
    database        = local.database_name
  }
}

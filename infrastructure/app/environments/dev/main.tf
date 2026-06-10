data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}

module "content" {
  source           = "../../stacks/content"
  region           = local.region
  account_id       = local.account_id
  supabase_project = { name = "Heart dev" }
}

module "firebase" {
  source        = "../../stacks/firebase"
  name_prefix   = "${var.name_prefix}-firebase"
  runtime       = var.python_runtime
  handler       = var.lambda_handler
  log_retention = var.log_retention
}

module "api" {
  source                       = "../../stacks/api"
  environment                  = "dev"
  region                       = local.region
  account_id                   = local.account_id
  name_prefix                  = "${var.name_prefix}-api"
  log_retention                = var.log_retention
  firebase_project_id          = var.firebase_project_id
  firebase_events_queue        = module.firebase.events_queue
  content_bucket               = module.content.content_bucket
  database                     = module.content.database
  account_deletion_offset_days = 2
  monitoring_email             = "info@heart-of.me"
  media_distribution           = "dev.media.heart-of.me"
}

module "assets" {
  source           = "../../stacks/assets"
  name_prefix      = "${var.name_prefix}-assets"
  runtime          = "python3.12" # Pillow wheels don't run on Lambda > 3.12
  handler          = var.lambda_handler
  log_retention    = 7
  content_bucket   = module.content.content_bucket
  api_events_queue = module.api.events_queue
}

module "cdn" {
  source                             = "../../stacks/cdn"
  media_distribution_ssl_certificate = "arn:aws:acm:us-east-1:583168578067:certificate/297c34bc-7a74-4cb1-82c4-71bfe0114eb7"
  media_distribution_aliases         = ["dev.media.heart-of.me"]
  web_distribution_ssl_certificate   = "arn:aws:acm:us-east-1:583168578067:certificate/2ac33117-c985-4f4d-a382-d2c8bad1766a"
  web_distribution_aliases           = ["dev.heart-of.me", "www.dev.heart-of.me"]
  firebase_auth_domain               = "heart-of-yours-dev.firebaseapp.com"
  content_bucket                     = module.content.content_bucket
  static_bucket                      = module.content.static_bucket
  api                                = module.api.api
}

module "monitoring" {
  source                = "../../stacks/monitoring"
  name_prefix           = "${var.name_prefix}-api"
  region                = local.region
  function_name         = module.api.function_name
  api_gateway_name      = module.api.api_gateway_name
  events_queue_name     = module.api.events_queue_name
  events_dlq_name       = module.api.events_dlq_name
  web_distribution_id   = module.cdn.web_distribution.id
  media_distribution_id = module.cdn.media_distribution.id
}

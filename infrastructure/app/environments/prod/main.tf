data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}

module "content" {
  source     = "../../stacks/content"
  region     = local.region
  account_id = local.account_id
}

module "firebase" {
  source        = "../../stacks/firebase"
  name_prefix   = "${var.name_prefix}-firebase"
  runtime       = var.python_runtime
  handler       = var.lambda_handler
  log_retention = 7
}

module "api" {
  source                       = "../../stacks/api"
  environment                  = "prod"
  region                       = local.region
  account_id                   = local.account_id
  name_prefix                  = "${var.name_prefix}-api"
  log_retention                = 30
  firebase_project_id          = var.firebase_project_id
  firebase_events_queue        = module.firebase.events_queue
  content_bucket               = module.content.content_bucket
  database                     = module.content.database
  account_deletion_offset_days = 30
  monitoring_email             = "info@heart-of.me"
  media_distribution           = "media.heart-of.me"
}

module "cdn" {
  source                             = "../../stacks/cdn"
  media_distribution_ssl_certificate = "arn:aws:acm:us-east-1:922419543441:certificate/a91ae5f9-d156-465b-9ea4-d3564a7175d6"
  media_distribution_aliases         = ["media.heart-of.me"]
  web_distribution_ssl_certificate   = "arn:aws:acm:us-east-1:922419543441:certificate/60a653e8-c734-4d9a-bd92-747e9f4e994a"
  web_distribution_aliases           = ["heart-of.me", "www.heart-of.me"]
  firebase_auth_domain               = "heart-of.me"
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

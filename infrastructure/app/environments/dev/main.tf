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
  source         = "../../stacks/firebase"
  name_prefix    = "${var.name_prefix}-firebase"
  runtime        = var.python_runtime
  handler        = var.lambda_handler
  log_retention  = var.log_retention
  events_enabled = var.events_enabled
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
  apple_sign_in                = local.apple_sign_in
  account_deletion_offset_days = 2
  monitoring_email             = "info@heart-of.me"
  media_distribution           = "dev.media.heart-of.me"
  events_enabled               = var.events_enabled
  custom_domain = {
    name            = "dev.api.heart-of.me"
    certificate_arn = "arn:aws:acm:ca-central-1:583168578067:certificate/43e5a2aa-7c62-4fa4-a137-9b35df1f47b6"
  }
}

module "assets" {
  source           = "../../stacks/assets"
  name_prefix      = "${var.name_prefix}-assets"
  runtime          = "python3.12" # Pillow wheels don't run on Lambda > 3.12
  handler          = var.lambda_handler
  log_retention    = 7
  content_bucket   = module.content.content_bucket
  api_events_queue = module.api.events_queue
  events_enabled   = var.events_enabled
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
  log_group_name        = module.api.log_group_name
  # No alarms in dev: the topic's subscriber is a human inbox, and dev is where
  # things are meant to break. Same opt-out as the deploy workflow's empty
  # MONITORING_TOPIC_ARN.
  alarm_topic_arn = ""
}

# Sign in with Apple. Only the key itself is a secret: the team, key and client
# ids are identifiers, and already sit in plaintext beside the provisioning
# profiles under the same prefix.
#
# Its own key, not prod's — a key is configured against a primary App ID, and
# prod's does not cover `me.heart-of.ios.dev`.
data "aws_s3_object" "apple_sign_in_key" {
  bucket = module.content.static_bucket.bucket
  key    = "secrets/appstore/AuthKey_${local.apple_key_id}.p8"

  # Terraform only populates `body` for content types it treats as text, and
  # `aws s3 cp` types a .p8 as application/pkcs8 — so this object is stored as
  # text/plain, unlike the App Store Connect key beside it. That is a hack, and
  # the failure it invites is silent: an empty body ships a blank
  # APPLE_PRIVATE_KEY, AppConfig reads the set as incomplete, and revocation
  # stops while deletions carry on. Caught here instead, at plan time.
  lifecycle {
    postcondition {
      condition     = can(regex("BEGIN PRIVATE KEY", self.body))
      error_message = "secrets/appstore/AuthKey_${local.apple_key_id}.p8 read back empty or unparseable - re-upload it with --content-type text/plain."
    }
  }
}

locals {
  # The filename carries it, so rotating the key is one edit here.
  apple_key_id = "B36L4GLHJD"

  apple_sign_in = {
    team_id     = "DFX2JYT8BM"
    key_id      = local.apple_key_id
    private_key = data.aws_s3_object.apple_sign_in_key.body
    client_ids  = ["me.heart-of.ios.dev"]
  }
}

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

module "api" {
  source              = "../../stacks/api"
  environment         = "dev"
  region              = local.region
  account_id          = local.account_id
  name_prefix         = "${var.name_prefix}-api"
  log_retention       = 7
  firebase_project_id = "heart-of-yours-dev"
  content_bucket      = module.content.content_bucket
  database            = module.content.database
}

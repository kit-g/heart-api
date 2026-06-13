variable "github_repos" {
  type        = list(string)
  default     = ["kit-g/heart-api", "kit-g/heart-of-yours"]
  description = "GitHub repos (owner/name) allowed to assume the deploy role."
}

variable "static_bucket" {
  type        = string
  description = "Holds shared static assets, the static site, and the deploy-time secrets file."
}

variable "buckets" {
  type        = list(string)
  description = "What S3 buckets to allow to get read access to"
}

variable "lambda_function_prefix" {
  type        = string
  default     = "heart-"
  description = "Allow `lambda:UpdateFunctionCode` on functions whose name starts with this."
}

variable "web_distribution_id" {
  type        = string
  description = "Web CloudFront distribution; invalidations target this."
}

variable "firebase_project_config" {
  description = "Firebase GCP project"
  type = object({
    project_id       = string
    region           = string
    ios_bundle_id    = string
    appstore_team_id = string
    appstore_app_id  = string
    android_app_id   = string
    android_sha_256  = list(string)
  })
}

data "aws_caller_identity" "this" {}
data "aws_region" "this" {}

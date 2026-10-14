variable "github_oidc_subjects" {
  type        = list(string)
  description = "Repository-scoped OIDC subjects allowed to assume this account's deploy role."

  validation {
    condition = length(var.github_oidc_subjects) > 0 && alltrue([
      for subject in var.github_oidc_subjects :
      can(regex("^repo:[^:*?]+/[^:*?]+:.+$", subject))
    ])
    error_message = "Trust exact repositories with a nonempty subject context; do not wildcard the owner or repository."
  }
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

variable "monitoring_topic_name" {
  type        = string
  default     = "monitoring"
  description = "SNS topic the deploy workflow publishes its run notification to; created by the app stack."
}

variable "web_distribution_id" {
  type        = string
  description = "Web CloudFront distribution; invalidations target this."
}

variable "media_distribution_id" {
  type        = string
  description = "Media CloudFront distribution; invalidations target this (e.g. after publishing static/exercises/)."
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
    android_sha_1    = list(string)
  })
}
variable "agent_roles" {
  type        = list(string)
  description = "Project roles granted to the heart-agent service account in the Firebase project."
}


data "aws_caller_identity" "this" {}
data "aws_region" "this" {}

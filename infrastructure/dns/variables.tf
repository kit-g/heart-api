variable "apex_domain" {
  type        = string
  default     = "heart-of.me"
  description = "The apex domain managed in this account."
}

variable "prod_web_distribution_domain_name" {
  type        = string
  description = "Domain name of the web CloudFront distribution. Update when the distribution is recreated."
}

variable "prod_media_distribution_domain_name" {
  type        = string
  description = "Domain name of the media CloudFront distribution. Update when the distribution is recreated."
}

variable "communications_email" {
  type    = string
  default = "info@heart-of.me"
}

variable "firebase_prod_project_id" {
  type = string
}

variable "prod_api_domain_name" {
  type        = string
  default     = ""
  description = "Regional endpoint behind the prod API Gateway custom domain. Empty until the app environment has created it: this zone has to carry the certificate validation record before that apply can succeed, so the alias lands on a second pass. Update when the domain name is recreated."
}

variable "prod_mcp_distribution_domain_name" {
  type        = string
  default     = ""
  description = "Domain name of the prod MCP host's CloudFront distribution (the api stack's `mcp_distribution_domain` output). Empty until the app environment has created it: this zone has to carry the certificate validation record before that apply can succeed, so the alias lands on a second pass. Update when the distribution is recreated."
}

variable "dev_name_servers" {
  type        = list(string)
  default     = []
  description = "The dev account's zone for dev.heart-of.me: the dev environment's `name_servers` output. Empty until that zone exists; set, it turns the whole dev subtree into a delegation."
}

# Fixed AWS-wide CloudFront alias zone — same for all distributions.
locals {
  cloudfront_zone_id = "Z2FDTNDATAQYW2"
}

# Fixed per-region alias zone for API Gateway regional endpoints — ca-central-1.
locals {
  apigw_regional_zone_id = "Z19DQILCV0OWEC"
}

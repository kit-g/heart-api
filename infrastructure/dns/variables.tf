variable "apex_domain" {
  type        = string
  default     = "heart-of.me"
  description = "The apex domain managed in this account."
}

variable "dev_web_distribution_domain_name" {
  type        = string
  description = "Domain name of the web CloudFront distribution. Update when the distribution is recreated."
}

variable "prod_web_distribution_domain_name" {
  type        = string
  description = "Domain name of the web CloudFront distribution. Update when the distribution is recreated."
}

variable "dev_media_distribution_domain_name" {
  type        = string
  description = "Domain name of the media CloudFront distribution. Update when the distribution is recreated."
}

variable "prod_media_distribution_domain_name" {
  type        = string
  description = "Domain name of the media CloudFront distribution. Update when the distribution is recreated."
}

variable "communications_email" {
  type    = string
  default = "info@heart-of.me"
}

variable "firebase_dev_project_id" {
  type = string
}

variable "firebase_prod_project_id" {
  type = string
}

variable "dev_api_domain_name" {
  type        = string
  default     = ""
  description = "Regional endpoint behind the dev API Gateway custom domain. Empty until the app environment has created it: this zone has to carry the certificate validation record before that apply can succeed, so the alias lands on a second pass. Update when the domain name is recreated."
}

variable "prod_api_domain_name" {
  type        = string
  default     = ""
  description = "Regional endpoint behind the prod API Gateway custom domain. Empty until the app environment has created it: this zone has to carry the certificate validation record before that apply can succeed, so the alias lands on a second pass. Update when the domain name is recreated."
}

# Fixed AWS-wide CloudFront alias zone — same for all distributions.
locals {
  cloudfront_zone_id = "Z2FDTNDATAQYW2"
}

# Fixed per-region alias zone for API Gateway regional endpoints — ca-central-1.
locals {
  apigw_regional_zone_id = "Z19DQILCV0OWEC"
}

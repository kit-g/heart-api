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

# Fixed AWS-wide CloudFront alias zone — same for all distributions.
locals {
  cloudfront_zone_id = "Z2FDTNDATAQYW2"
}

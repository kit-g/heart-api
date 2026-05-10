variable "apex_domain" {
  type        = string
  default     = "heart-of.me"
  description = "The apex domain managed in this account."
}

variable "web_distribution_domain_name" {
  type        = string
  default     = "d1pfa4npfjx633.cloudfront.net"
  description = "Domain name of the web CloudFront distribution. Update when the distribution is recreated."
}

variable "media_distribution_domain_name" {
  type        = string
  default     = "d3h38bni0fkad4.cloudfront.net"
  description = "Domain name of the media CloudFront distribution. Update when the distribution is recreated."
}

variable "communications_email" {
  type    = string
  default = "info@heart-of.me"
}

variable "firebase_dev_project_id" {
  type    = string
  default = "heart-of-yours-dev"
}

# Fixed AWS-wide CloudFront alias zone — same for all distributions.
locals {
  cloudfront_zone_id = "Z2FDTNDATAQYW2"
}

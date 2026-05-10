variable "media_distribution_aliases" {
  type        = set(string)
  description = "CNAMES of the media distribution"
}

variable "web_distribution_aliases" {
  type        = set(string)
  description = "CNAMES of the web distribution"
}

variable "firebase_auth_domain" {
  type        = string
  description = "DNS name of the Firebase auth app"
}

variable "media_distribution_ssl_certificate" {
  type        = string
  description = "AWS ACM ARN for media. subdomain"

  validation {
    condition     = can(regex("^arn:aws:acm:[a-z]{2}-[a-z]+-[0-9]{1}:[0-9]{12}:certificate/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$", var.media_distribution_ssl_certificate))
    error_message = "Certificate ARN must be a valid AWS ACM ARN format (e.g., arn:aws:acm:us-east-1:583168578067:certificate/297c34bc-7a74-4cb1-82c4-71bfe0114eb7)."
  }
}

variable "web_distribution_ssl_certificate" {
  type        = string
  description = "AWS ACM ARN for the main domain"

  validation {
    condition     = can(regex("^arn:aws:acm:[a-z]{2}-[a-z]+-[0-9]{1}:[0-9]{12}:certificate/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$", var.web_distribution_ssl_certificate))
    error_message = "Certificate ARN must be a valid AWS ACM ARN format (e.g., arn:aws:acm:us-east-1:583168578067:certificate/297c34bc-7a74-4cb1-82c4-71bfe0114eb7)."
  }
}


variable "api" {
  type = object({
    domain_name = string
    stage_path  = string
  })
}

variable "static_bucket" {
  type = object({
    id                          = string
    arn                         = string
    bucket_regional_domain_name = string
  })
}

variable "content_bucket" {
  type = object({
    id                          = string
    arn                         = string
    bucket_regional_domain_name = string
  })
}

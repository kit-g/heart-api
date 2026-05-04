variable "region" {
  description = "AWS region"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.region))
    error_message = "Region must be a valid AWS region format (e.g., us-east-1, eu-west-2)."
  }
}

variable "account_id" {
  description = "AWS account ID"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Account ID must be a 12-digit number."
  }
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

variable "media_distribution_aliases" {
  type = set(string)
  description = "CNAMES of the media distribution"
}

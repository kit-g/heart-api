variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  type        = string
  description = "Environment ID"
}

variable "log_retention" {
  description = "How long CloudWatch logs will be preserved, in days"
  type        = number
}

variable "firebase_project_id" {
  type        = string
  description = "Firebase project ID, used for authentication etc."
}

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

variable "content_bucket" {
  type = object({
    bucket = string
    arn    = string
  })
}

variable "static_bucket" {
  type = object({
    bucket = string
    arn    = string
  })
}


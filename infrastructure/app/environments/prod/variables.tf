variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project               = "heart"
    Environment           = "dev"
    Owner                 = "heart"
    AppManagerCFNStackKey = "heart"
  }
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "heart"
}

variable "python_runtime" {
  description = "AWS Lambda runtime for every Python service in this env."
  type        = string
  default     = "python3.14"
}

variable "lambda_handler" {
  description = "Lambda entrypoint convention shared across services: file `app.py`, function `handler`."
  type        = string
  default     = "app.handler"
}

variable "firebase_project_id" {
  type        = string
  description = "Firebase project ID"
}

variable "log_retention" {
  type        = number
  description = "How many days will keep logs"
}

variable "dev_name_servers" {
  type        = list(string)
  description = "The dev account's name servers, which the apex delegates dev.heart-of.me to: the dev environment's `name_servers` output. That state is in another account, so the value crosses by hand."

  # A Route 53 zone has four servers; anything else is a half-pasted list.
  validation {
    condition     = length(var.dev_name_servers) == 4
    error_message = "dev_name_servers is the dev environment's name_servers output, all four of them."
  }
}

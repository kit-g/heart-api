variable "name_prefix" {
  type        = string
  description = "Prefix for resource names (e.g. 'heart-firebase')."
}

variable "runtime" {
  type        = string
  description = "Lambda runtime identifier (e.g. python3.14)."
}

variable "handler" {
  type        = string
  description = "Lambda entrypoint (e.g. app.handler)."
}

variable "log_retention" {
  type        = number
  default     = 7
  description = "Lambda log retention in days."
}
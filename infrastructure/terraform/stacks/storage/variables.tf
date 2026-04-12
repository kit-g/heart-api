variable "enable_deletion_protection" {
  type        = bool
  description = "Whether DynamoDB tables should have deletion protection"
}

variable "point_in_time_recovery" {
  type = object({
    enabled = bool
    days    = number
  })
  description = "Whether DynamoDB tables should have point-in-time recovery"
}

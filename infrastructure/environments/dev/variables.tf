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

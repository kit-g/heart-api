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
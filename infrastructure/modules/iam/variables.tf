variable "name" {
  type = string
}

variable "description" {
  type    = string
  default = null
}

variable "service_principals" {
  type    = list(string)
  default = ["lambda.amazonaws.com"]
}

variable "managed_policy_arns" {
  type    = list(string)
  default = []
}

variable "inline_policies" {
  type    = map(string) # name => JSON policy document
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}

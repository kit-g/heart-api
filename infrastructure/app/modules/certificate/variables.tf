variable "domain_name" {
  type        = string
  description = "The name the certificate is for."
}

variable "subject_alternative_names" {
  type        = list(string)
  default     = []
  description = "Further names on the same certificate (www, say). Each is validated like the first, so each has to be in the same zone."
}

variable "zone_id" {
  type        = string
  description = "The Route 53 zone that holds every name on the certificate; the validation records go there."
}

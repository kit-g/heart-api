variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
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

variable "log_retention" {
  type        = number
  description = "How many days will keep logs"
}

variable "firebase_project_id" {
  type        = string
  description = "Firebase project ID"
}

variable "events_enabled" {
  type        = bool
  default     = true
  description = "Enable the SQS->Lambda event source mappings across all services. Set false to stop idle pollers from consuming SQS requests."
}
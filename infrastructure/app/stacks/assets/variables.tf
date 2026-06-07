variable "name_prefix" {
  type        = string
  description = "Prefix for resource names (e.g. 'heart-assets')."
}

variable "runtime" {
  type        = string
  description = "Lambda runtime identifier. Pinned to python3.12 by the caller: Pillow's wheels don't run on Lambda runtimes above 3.12."
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

variable "content_bucket" {
  description = "Content bucket: raw uploads land under exercise-uploads/, processed assets are written under exercises/."
  type = object({
    bucket = string
    arn    = string
  })
}

variable "api_events_queue" {
  description = "The API's events SQS queue — this service posts `exercise.asset.processed` here for the API to persist."
  type = object({
    arn = string
    url = string
  })
}

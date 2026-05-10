variable "name_prefix" {
  type        = string
  description = "Prefix for the dashboard name."
}

variable "region" {
  type        = string
  description = "AWS region the resources live in (metrics are per-region)."
}

variable "function_name" {
  type        = string
  description = "Name of the API Lambda function."
}

variable "api_gateway_name" {
  type        = string
  description = "Name of the API Gateway REST API."
}

variable "events_queue_name" {
  type        = string
  description = "Name of the events SQS queue."
}

variable "events_dlq_name" {
  type        = string
  description = "Name of the events SQS DLQ."
}

variable "web_distribution_id" {
  type        = string
  description = "CloudFront web distribution ID."
}

variable "media_distribution_id" {
  type        = string
  description = "CloudFront media distribution ID."
}

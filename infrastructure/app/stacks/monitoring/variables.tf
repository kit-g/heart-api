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

variable "log_group_name" {
  type        = string
  description = "Log group the API Lambda writes to; the SEVERE metric filter reads it."
}

variable "alarm_topic_arn" {
  type        = string
  default     = ""
  description = <<-EOT
    SNS topic every alarm notifies. An empty string opts the environment out of
    alarms entirely — the dashboard is still built — the same way an empty
    MONITORING_TOPIC_ARN opts the dev deploy out of its notification. Dev opts
    out: the endpoint behind the topic is a human inbox, and dev breaks on
    purpose.
  EOT
}

variable "concurrency_alarm_threshold" {
  type        = number
  default     = 8
  description = <<-EOT
    ConcurrentExecutions level that fires the leading-indicator alarm. Set below
    the account's concurrent-execution limit, which is where throttling starts:
    this is the warning that arrives while a limit increase is still a choice.
  EOT
}

locals {
  # CloudFront metrics are always in us-east-1.
  cf_region = "us-east-1"

  widgets = [
    # Row 1 — Lambda
    {
      type   = "metric"
      x      = 0
      y      = 0
      width  = 8
      height = 6
      properties = {
        view    = "timeSeries"
        stacked = false
        region  = var.region
        stat    = "Sum"
        title   = "Lambda — invocations & errors"
        metrics = [
          ["AWS/Lambda", "Invocations", "FunctionName", var.function_name],
          [".", "Errors", ".", "."],
          [".", "Throttles", ".", "."],
        ]
      }
    },
    {
      type   = "metric"
      x      = 8
      y      = 0
      width  = 8
      height = 6
      properties = {
        view    = "timeSeries"
        stacked = false
        region  = var.region
        title   = "Lambda — duration (p50/p99)"
        metrics = [
          ["AWS/Lambda", "Duration", "FunctionName", var.function_name, { stat = "p50" }],
          [".", ".", ".", ".", { stat = "p99" }],
        ]
      }
    },
    {
      type   = "metric"
      x      = 16
      y      = 0
      width  = 8
      height = 6
      properties = {
        view    = "timeSeries"
        stacked = false
        region  = var.region
        stat    = "Maximum"
        title   = "Lambda — concurrent executions"
        metrics = [
          ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", var.function_name],
        ]
      }
    },

    # Row 2 — SQS
    {
      type   = "metric"
      x      = 0
      y      = 6
      width  = 12
      height = 6
      properties = {
        view    = "timeSeries"
        stacked = false
        region  = var.region
        stat    = "Average"
        title   = "SQS — queue depth"
        metrics = [
          ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.events_queue_name],
          [".", ".", ".", var.events_dlq_name],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 6
      width  = 12
      height = 6
      properties = {
        view    = "timeSeries"
        stacked = false
        region  = var.region
        stat    = "Maximum"
        title   = "SQS — age of oldest message"
        metrics = [
          ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", var.events_queue_name],
          [".", ".", ".", var.events_dlq_name],
        ]
      }
    },

    # Row 3 — API Gateway
    {
      type   = "metric"
      x      = 0
      y      = 12
      width  = 12
      height = 6
      properties = {
        view    = "timeSeries"
        stacked = false
        region  = var.region
        stat    = "Sum"
        title   = "API Gateway — requests & errors"
        metrics = [
          ["AWS/ApiGateway", "Count", "ApiName", var.api_gateway_name],
          [".", "4XXError", ".", "."],
          [".", "5XXError", ".", "."],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 12
      width  = 12
      height = 6
      properties = {
        view    = "timeSeries"
        stacked = false
        region  = var.region
        title   = "API Gateway — latency (p50/p99)"
        metrics = [
          ["AWS/ApiGateway", "Latency", "ApiName", var.api_gateway_name, { stat = "p50" }],
          [".", ".", ".", ".", { stat = "p99" }],
        ]
      }
    },

    # Row 4 — CloudFront (always us-east-1 metrics, regardless of distro home region)
    {
      type   = "metric"
      x      = 0
      y      = 18
      width  = 12
      height = 6
      properties = {
        view    = "timeSeries"
        stacked = false
        region  = local.cf_region
        stat    = "Sum"
        title   = "CloudFront — requests"
        metrics = [
          ["AWS/CloudFront", "Requests", "DistributionId", var.web_distribution_id, "Region", "Global"],
          [".", ".", ".", var.media_distribution_id, ".", "."],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 18
      width  = 12
      height = 6
      properties = {
        view    = "timeSeries"
        stacked = false
        region  = local.cf_region
        stat    = "Average"
        title   = "CloudFront — 4xx / 5xx rate"
        metrics = [
          ["AWS/CloudFront", "4xxErrorRate", "DistributionId", var.web_distribution_id, "Region", "Global"],
          [".", "5xxErrorRate", ".", ".", ".", "."],
          [".", "4xxErrorRate", ".", var.media_distribution_id, ".", "."],
          [".", "5xxErrorRate", ".", ".", ".", "."],
        ]
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name_prefix}-overview"
  dashboard_body = jsonencode({ widgets = local.widgets })
}

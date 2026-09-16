# Alarms, as one map + one resource — the same shape the dashboard's widgets use,
# and what lets `tests/budget.tftest.hcl` assert the count from outside.
#
# The CloudWatch always-free tier is 10 alarm metrics per account. These spend
# seven and leave three, so the next incident has somewhere to go without a
# billing decision attached. Two things stay out of the tier and so out of here:
# composite alarms, and anomaly-detection or metric-math alarms.
#
# Every alarm is single-metric, one evaluation period, and `notBreaching` on
# missing data: these metrics are absent when nothing is happening, and absent
# must not read as broken. No `ok_actions` — the topic's subscriber is a human
# inbox that also receives support mail, so recovery is something to read on the
# dashboard rather than another message.

locals {
  # `tomap` on every dimensions value is load-bearing, not decoration: for_each
  # converts this object to a map, which requires all seven values to share one
  # type, and `{ QueueName = … }` and `{ FunctionName = … }` are different object
  # types. Dropping it fails the plan with "attribute types must all match".
  #
  # CloudFront's 4xx/5xx rates are deliberately not alarmed: those metrics only
  # exist in us-east-1, so an alarm on them needs a second, aliased provider
  # threaded through this module. They stay on the dashboard.
  alarms = {
    # Every permanent event failure is written to the DLQ by design, so anything
    # sitting here is a real one that no retry will clear. Maximum rather than
    # Sum: the metric is a queue depth, and summing depths over a period is
    # meaningless.
    events_dlq_not_empty = {
      description = "An event record failed permanently and was parked in the DLQ."
      namespace   = "AWS/SQS"
      metric_name = "ApproximateNumberOfMessagesVisible"
      dimensions  = tomap({ QueueName = var.events_dlq_name })
      statistic   = "Maximum"
      period      = 300
      operator    = "GreaterThanOrEqualToThreshold"
      threshold   = 1
    }

    # A stalled queue, not a retrying one. A record that fails three times takes
    # roughly 15 minutes to exhaust `maxReceiveCount` against a 300s visibility
    # timeout, and lands in the DLQ — which the alarm above already reports. 30
    # minutes means nothing is draining the queue at all: the event source
    # mapping disabled, or invocations throttled.
    events_queue_stalled = {
      description = "Nothing is draining the events queue."
      namespace   = "AWS/SQS"
      metric_name = "ApproximateAgeOfOldestMessage"
      dimensions  = tomap({ QueueName = var.events_queue_name })
      statistic   = "Maximum"
      period      = 300
      operator    = "GreaterThanThreshold"
      threshold   = 1800
    }

    # An invocation that failed outright. Worth one alarm on its own because the
    # event path now reports transient failures this way, on purpose, so that
    # SQS redelivers — the metric carries meaning it did not carry before.
    lambda_errors = {
      description = "The API function failed an invocation."
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      dimensions  = tomap({ FunctionName = var.function_name })
      statistic   = "Sum"
      period      = 300
      operator    = "GreaterThanOrEqualToThreshold"
      threshold   = 1
    }

    # One function serves both HTTP requests and the event queue, so throttling
    # is also how a burst of events becomes user-visible request failures.
    lambda_throttles = {
      description = "Invocations were throttled: the concurrency limit was reached."
      namespace   = "AWS/Lambda"
      metric_name = "Throttles"
      dimensions  = tomap({ FunctionName = var.function_name })
      statistic   = "Sum"
      period      = 300
      operator    = "GreaterThanOrEqualToThreshold"
      threshold   = 1
    }

    # The warning ahead of the throttling above, while a limit increase is still
    # a decision rather than an incident.
    lambda_near_concurrency_limit = {
      description = "Concurrent executions are approaching the account limit."
      namespace   = "AWS/Lambda"
      metric_name = "ConcurrentExecutions"
      dimensions  = tomap({ FunctionName = var.function_name })
      statistic   = "Maximum"
      period      = 300
      operator    = "GreaterThanOrEqualToThreshold"
      threshold   = var.concurrency_alarm_threshold
    }

    # 5xx only. 4xx is the client's business and belongs to whatever watches
    # clients; a 5xx is always this API's.
    api_server_errors = {
      description = "The API returned 5xx responses."
      namespace   = "AWS/ApiGateway"
      metric_name = "5XXError"
      dimensions  = tomap({ ApiName = var.api_gateway_name })
      statistic   = "Sum"
      period      = 300
      operator    = "GreaterThanOrEqualToThreshold"
      threshold   = 1
    }

    # The catch-all, and the only alarm that sees a failure the platform metrics
    # cannot: something the process handled and logged rather than crashed on.
    # Fed by the metric filter below.
    severe_log_events = {
      description = "The API logged a SEVERE record."
      namespace   = local.log_metric_namespace
      metric_name = aws_cloudwatch_log_metric_filter.severe.metric_transformation[0].name
      dimensions  = tomap({})
      statistic   = "Sum"
      period      = 300
      operator    = "GreaterThanOrEqualToThreshold"
      threshold   = 1
    }
  }

  log_metric_namespace = "Heart/API"
  alarms_enabled       = var.alarm_topic_arn != ""
}

# Prod logs one JSON object per record, so the filter matches a field rather
# than scraping text. A filter is free; the metric it publishes counts against
# the ten custom metrics the free tier allows.
resource "aws_cloudwatch_log_metric_filter" "severe" {
  name           = "${var.name_prefix}-severe-logs"
  log_group_name = var.log_group_name
  pattern        = "{ $.level = \"SEVERE\" }"

  metric_transformation {
    name      = "SevereLogEvents"
    namespace = local.log_metric_namespace
    value     = "1"
    # Without this the metric reports nothing when no SEVERE record is written,
    # and an alarm reading nothing sits in INSUFFICIENT_DATA instead of OK.
    default_value = 0
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms_enabled ? local.alarms : {}

  alarm_name          = "${var.name_prefix}-${replace(each.key, "_", "-")}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  dimensions          = each.value.dimensions
  statistic           = each.value.statistic
  period              = each.value.period
  comparison_operator = each.value.operator
  threshold           = each.value.threshold
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.alarm_topic_arn]
}

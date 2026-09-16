# Tests for the monitoring stack.
#
# Run from this module's directory:  terraform init && terraform test
#
# Plan-only, no credentials: everything asserted here is decided locally, from
# the alarm map and the dashboard's rendered JSON.

provider "aws" {
  region                      = "ca-central-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

variables {
  name_prefix           = "heart-api"
  region                = "ca-central-1"
  function_name         = "heart-api"
  api_gateway_name      = "heart-api"
  events_queue_name     = "heart-api-events"
  events_dlq_name       = "heart-api-events-dlq"
  web_distribution_id   = "E1WEB"
  media_distribution_id = "E1MEDIA"
  log_group_name        = "/aws/lambda/heart-api"
}

run "alarms_stay_inside_the_free_tier" {
  command = plan

  variables {
    alarm_topic_arn = "arn:aws:sns:ca-central-1:000000000000:monitoring"
  }

  # The CloudWatch always-free tier is ten alarm metrics per account. Every
  # alarm here watches exactly one metric, so the resource count is the spend.
  # This is a budget, not a limit imposed by anything AWS will refuse — going
  # over starts a bill instead of an error, which is why it is asserted.
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) <= 10
    error_message = "More than ten alarms: the eleventh leaves the free tier. Retire one or accept the cost deliberately."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) > 0
    error_message = "A topic was supplied but no alarm was planned"
  }

  # Every alarm must actually notify. An alarm with no action is a coloured
  # square on a page nobody has open.
  assert {
    condition = alltrue([
      for alarm in values(aws_cloudwatch_metric_alarm.this) :
      contains(alarm.alarm_actions, var.alarm_topic_arn)
    ])
    error_message = "Every alarm must notify the topic"
  }

  # Absent data is the normal state for all of these: no errors, no throttles,
  # an empty DLQ. Anything else here would alarm on quiet.
  assert {
    condition = alltrue([
      for alarm in values(aws_cloudwatch_metric_alarm.this) :
      alarm.treat_missing_data == "notBreaching"
    ])
    error_message = "Missing data must not read as breaching"
  }
}

run "an_empty_topic_opts_the_environment_out" {
  command = plan

  variables {
    alarm_topic_arn = ""
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 0
    error_message = "An empty topic ARN must plan no alarms"
  }

  # The dashboard is not part of the opt-out: it costs nothing and dev wants it.
  assert {
    condition     = aws_cloudwatch_dashboard.this.dashboard_name == "heart-api-overview"
    error_message = "The dashboard should be built regardless of alarms"
  }
}

resource "aws_scheduler_schedule_group" "accounts" {
  name = "accounts"
}

resource "aws_sns_topic" "monitoring" {
  name = "monitoring"
}

resource "aws_api_gateway_rest_api" "api" {
  name = "heart-api"

  # Regional, not the provider's edge-optimized default. Edge-optimized fronts
  # the API with an AWS-managed CloudFront distribution; every route here is
  # authenticated and uncacheable, so all that buys is TLS termination nearer
  # the caller, and it forces the custom domain's certificate into us-east-1.
  # The execute-api hostname survives the switch, so builds pinned to it keep
  # working through the cutover - they just reach the region directly.
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

locals {
  # The version clients carry in the path. Deliberately a separate literal from
  # the stage name below: mapping one onto the other is what lets the stage be
  # renamed or swapped without a client release.
  api_base_path = "v1"
}

# Null until the certificate is issued, which keeps the stack appliable before
# one exists - the same opt-out the monitoring stack gives `alarm_topic_arn`.
# Without it the API is reachable only at its execute-api hostname.
resource "aws_api_gateway_domain_name" "api" {
  count = var.custom_domain == null ? 0 : 1

  domain_name              = var.custom_domain.name
  regional_certificate_arn = var.custom_domain.certificate_arn
  security_policy          = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "api" {
  count = var.custom_domain == null ? 0 : 1

  api_id      = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.v1.stage_name
  domain_name = aws_api_gateway_domain_name.api[0].domain_name
  base_path   = local.api_base_path
}

resource "aws_lambda_permission" "api_invoke" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${aws_api_gateway_rest_api.api.id}/*"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  authorization = "NONE"
  http_method   = "ANY"
  resource_id   = aws_api_gateway_resource.proxy.id
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(
      jsonencode(
        [
          aws_api_gateway_rest_api.api.id,
          aws_api_gateway_resource.proxy.id,
          aws_api_gateway_method.proxy.id,
          aws_api_gateway_integration.proxy.id,
          aws_api_gateway_gateway_response.errors,
        ]
      )
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "v1" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "v1"
}

# A backstop, not a quota: per-account limits are the API's own job, and a
# flood of requests with invalid tokens never reaches them. With one
# {proxy+} resource the ceiling can only be stage-wide.
resource "aws_api_gateway_method_settings" "throttle" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.v1.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = var.throttle.rate
    throttling_burst_limit = var.throttle.burst
  }
}

# Errors API Gateway answers itself, before or instead of the function, in the
# API's own error shape ({error, code, reason}): a caller reads one shape
# whichever layer refused it. Types not listed here fall back to the two
# defaults. Two refusals come before any of this and keep AWS's own body: a
# path outside /v1, at the custom domain ({"message": "Forbidden"}), and a body
# over 10 MB (a plain-text 413), so REQUEST_TOO_LARGE is never used.
locals {
  gateway_errors = {
    # The throttle, with the Retry-After AWS's default leaves out: scripts and
    # MCP hosts back off by it.
    THROTTLED = {
      status  = "429"
      headers = { "gatewayresponse.header.Retry-After" = "'1'" }
      body    = { error = "too many requests", code = "throttled", reason = "the API is busy; try again shortly", retryAfter = 1 }
    }
    # A path with no method: only the stage root, since {proxy+} takes the
    # rest. AWS calls it a missing token; it is a missing route.
    MISSING_AUTHENTICATION_TOKEN = {
      status = "404"
      body   = { error = "no such route", code = "route_not_found" }
    }
    INTEGRATION_TIMEOUT = {
      status = "504"
      body   = { error = "timed out", code = "timeout", reason = "the request took longer than API Gateway's 29 seconds" }
    }
    # Everything else, AWS's own message as the reason. A crashed or throttled
    # function lands here as a 5xx.
    DEFAULT_4XX = {
      body = { error = "bad request", code = "gateway_rejected", reason = "$context.error.message" }
    }
    DEFAULT_5XX = {
      body = { error = "server error", code = "server_error", reason = "$context.error.message" }
    }
  }
}

resource "aws_api_gateway_gateway_response" "errors" {
  for_each = local.gateway_errors

  rest_api_id         = aws_api_gateway_rest_api.api.id
  response_type       = each.key
  status_code         = lookup(each.value, "status", null)
  response_parameters = lookup(each.value, "headers", null)

  response_templates = {
    "application/json" = jsonencode(each.value.body)
  }
}

moved {
  from = aws_api_gateway_gateway_response.throttled
  to   = aws_api_gateway_gateway_response.errors["THROTTLED"]
}

resource "aws_sqs_queue" "events_dlq" {
  name                      = "${var.name_prefix}-events-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "events" {
  name                       = "${var.name_prefix}-events"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.events.arn
  function_name    = aws_lambda_function.api.arn
  batch_size       = 10
  enabled          = var.events_enabled
}

resource "aws_cloudwatch_event_rule" "s3_image_uploads" {
  name        = "${var.name_prefix}-s3-image-uploads"
  description = "Capture S3 image uploads to content bucket"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.content_bucket.bucket]
      }
      object = {
        key = [
          { prefix = "uploads/" },
        ]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "send_to_sqs" {
  rule      = aws_cloudwatch_event_rule.s3_image_uploads.name
  target_id = "send-to-sqs"
  arn       = aws_sqs_queue.events.arn
}

resource "aws_sqs_queue_policy" "allow_eventbridge" {
  queue_url = aws_sqs_queue.events.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.events.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.s3_image_uploads.arn
          }
        }
      }
    ]
  })
}

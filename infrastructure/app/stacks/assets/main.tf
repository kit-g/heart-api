resource "aws_sqs_queue" "events_dlq" {
  name                      = "${var.name_prefix}-events-dlq"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "events" {
  name                       = "${var.name_prefix}-events"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400 # 1 day

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_cloudwatch_log_group" "assets" {
  name              = "/aws/lambda/${var.name_prefix}"
  retention_in_days = var.log_retention
}

resource "aws_lambda_function" "assets" {
  function_name    = var.name_prefix
  description      = "Part of Heart: assets pipeline — exercise media processing"
  role             = module.assets_role.role_arn
  runtime          = var.runtime
  handler          = var.handler
  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256
  architectures    = ["arm64"]
  memory_size      = 1024 # Pillow decode/resize of multi-MB GIFs
  timeout          = 120
  depends_on       = [aws_cloudwatch_log_group.assets]

  environment {
    variables = {
      API_EVENTS_QUEUE_URL = var.api_events_queue.url
      LOG_LEVEL            = "INFO"
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn        = aws_sqs_queue.events.arn
  function_name           = aws_lambda_function.assets.arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
  enabled                 = var.events_enabled
}

# Raw exercise uploads (content bucket, exercise-uploads/ prefix) -> EventBridge
# -> this service's queue. Distinct from the API's uploads/ rule.
resource "aws_cloudwatch_event_rule" "exercise_uploads" {
  name        = "${var.name_prefix}-exercise-uploads"
  description = "Capture raw exercise asset uploads to the content bucket"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.content_bucket.bucket]
      }
      object = {
        key = [
          { prefix = "exercise-uploads/" },
        ]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "send_to_sqs" {
  rule      = aws_cloudwatch_event_rule.exercise_uploads.name
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
            "aws:SourceArn" = aws_cloudwatch_event_rule.exercise_uploads.arn
          }
        }
      }
    ]
  })
}

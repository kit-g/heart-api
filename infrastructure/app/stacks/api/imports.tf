# An import the parser read only in part is kept in the content bucket under
# imports/partial/ for a look at what it refused. The bucket already publishes
# object events to EventBridge (the content stack); this turns the ones under
# that prefix into a note on the monitoring topic, the way the API itself
# announces a parked import. Parked files (imports/parked/) are announced by
# the API at the moment they are kept, so they are not matched here.
resource "aws_cloudwatch_event_rule" "partial_imports" {
  name        = "${var.name_prefix}-partial-imports"
  description = "A partially read import was kept in the content bucket"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.content_bucket.bucket]
      }
      object = {
        key = [
          { prefix = "imports/partial/" },
        ]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "partial_imports_to_monitoring" {
  rule      = aws_cloudwatch_event_rule.partial_imports.name
  target_id = "monitoring"
  arn       = aws_sns_topic.monitoring.arn

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
      size   = "$.detail.object.size"
    }
    # the message is the whole SNS body, so a JSON string
    input_template = "\"A partially read import was kept at s3://<bucket>/<key> (<size> bytes): rows were skipped. Worth a look at what the parser refused.\""
  }
}

# EventBridge publishes to a topic only with the topic's own say-so; the
# account's default statement is restated so the policy replaces, not narrows,
# what the topic allowed before.
resource "aws_sns_topic_policy" "monitoring" {
  arn = aws_sns_topic.monitoring.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "__default_statement_ID"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "SNS:Publish",
          "SNS:Subscribe",
          "SNS:Receive",
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:ListSubscriptionsByTopic",
          "SNS:DeleteTopic",
          "SNS:AddPermission",
          "SNS:RemovePermission",
        ]
        Resource = aws_sns_topic.monitoring.arn
        Condition = {
          StringEquals = {
            "AWS:SourceOwner" = var.account_id
          }
        }
      },
      {
        Sid    = "AllowEventBridge"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.monitoring.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.partial_imports.arn
          }
        }
      },
    ]
  })
}

data "aws_iam_policy_document" "content_rw" {
  statement {
    sid       = "ReadRawUploads"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.content_bucket.arn}/exercise-uploads/*"]
  }
  statement {
    sid       = "WriteProcessedAssets"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.content_bucket.arn}/exercises/*"]
  }
}

data "aws_iam_policy_document" "sqs_consume" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.events.arn]
  }
}

# Hand the processed result to the API to persist — the API owns the DB.
data "aws_iam_policy_document" "api_events_send" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [var.api_events_queue.arn]
  }
}

module "assets_role" {
  source      = "../../modules/iam"
  name        = "${var.name_prefix}-function-role"
  description = "Assets pipeline Lambda role"
  inline_policies = {
    "content_rw"      = data.aws_iam_policy_document.content_rw.json
    "sqs_consume"     = data.aws_iam_policy_document.sqs_consume.json
    "api_events_send" = data.aws_iam_policy_document.api_events_send.json
  }
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
}

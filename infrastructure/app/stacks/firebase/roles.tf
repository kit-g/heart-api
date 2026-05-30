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

data "aws_iam_policy_document" "sqs_dlq" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.events_dlq.arn]
  }
}

module "firebase_role" {
  source      = "../../modules/iam"
  name        = "${var.name_prefix}-function-role"
  description = "Firebase service Lambda role"
  inline_policies = {
    "sqs_consume" = data.aws_iam_policy_document.sqs_consume.json
    "sqs_dlq"     = data.aws_iam_policy_document.sqs_dlq.json
  }
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
}
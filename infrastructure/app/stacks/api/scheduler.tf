resource "aws_iam_role" "scheduler" {
  name               = "${var.name_prefix}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
}

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy" "scheduler_sqs_send" {
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_sqs_send.json
}

data "aws_iam_policy_document" "scheduler_sqs_send" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.events.arn]
  }
}

resource "aws_sns_topic_subscription" "monitoring_email" {
  count     = var.monitoring_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.monitoring.arn
  protocol  = "email"
  endpoint  = var.monitoring_email
}

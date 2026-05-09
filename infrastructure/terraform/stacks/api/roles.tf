data "aws_iam_policy_document" "scheduler_manage" {
  statement {
    sid = "SchedulerManage"
    actions = [
      "scheduler:CreateSchedule",
      "scheduler:DeleteSchedule",
      "scheduler:GetSchedule",
    ]
    resources = [
      "arn:aws:scheduler:${var.region}:${var.account_id}:schedule/${aws_scheduler_schedule_group.accounts.name}/*",
    ]
  }
}

data "aws_iam_policy_document" "sns_publish" {
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.monitoring.arn]
  }
}

data "aws_iam_policy_document" "content_bucket" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:GetObjectTagging",
      "s3:PutObjectTagging",
      "s3:DeleteObject",
    ]
    resources = [
      var.content_bucket.arn,
      "${var.content_bucket.arn}/*",
    ]
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

data "aws_iam_policy_document" "sqs_dlq" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.events_dlq.arn]
  }
}

data "aws_iam_policy_document" "pass_scheduler_role" {
  statement {
    sid     = "PassSchedulerRole"
    actions = ["iam:PassRole"]
    resources = [aws_iam_role.scheduler.arn]
  }
}

module "api_role" {
  source      = "../../modules/iam"
  name        = "${var.name_prefix}-function-role"
  description = "API function lambda role"
  inline_policies = {
    "scheduler_manage"   = data.aws_iam_policy_document.scheduler_manage.json
    "sns_publish"        = data.aws_iam_policy_document.sns_publish.json
    "content_bucket"     = data.aws_iam_policy_document.content_bucket.json
    "sqs_consume"        = data.aws_iam_policy_document.sqs_consume.json
    "sqs_dlq"            = data.aws_iam_policy_document.sqs_dlq.json
    "pass_scheduler_role" = data.aws_iam_policy_document.pass_scheduler_role.json
  }
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
}

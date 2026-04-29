data "aws_iam_policy_document" "scheduler_manage" {
  statement {
    sid = "SchedulerManage"
    actions = [
      "scheduler:CreateSchedule",
      "scheduler:DeleteSchedule",
    ]
    resources = [
      aws_scheduler_schedule_group.accounts.arn,
      "${aws_scheduler_schedule_group.accounts.arn}/*",
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
    effect  = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObject",
    ]
    resources = [
      var.content_bucket.arn,
      "${var.content_bucket.arn}/*",
    ]
  }
}

module "api_role" {
  source      = "../../modules/iam"
  name        = "${var.name_prefix}-function-role"
  description = "API function lambda role"
  inline_policies = {
    "scheduler_manage" = data.aws_iam_policy_document.scheduler_manage.json
    "sns_publish"      = data.aws_iam_policy_document.sns_publish.json
    "content_bucket"      = data.aws_iam_policy_document.content_bucket.json
  }
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
}

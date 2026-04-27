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

module "api_role" {
  source      = "../../modules/iam"
  name        = "${var.name_prefix}-function-role"
  description = "API function lambda role"
  inline_policies = {
    "scheduler_manage" = data.aws_iam_policy_document.scheduler_manage.json
  }
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
}

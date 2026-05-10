# proactively defining log groups to be able to manage them from code
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${var.name_prefix}"
  retention_in_days = var.log_retention
}
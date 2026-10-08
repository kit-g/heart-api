# What the environment's Route 53 alias for the API points at.
output "custom_domain" {
  value = var.custom_domain == null ? null : {
    name           = aws_api_gateway_domain_name.api[0].domain_name
    domain_name    = aws_api_gateway_domain_name.api[0].regional_domain_name
    hosted_zone_id = aws_api_gateway_domain_name.api[0].regional_zone_id
  }
}

output "function_name" {
  value = aws_lambda_function.api.function_name
}

output "api_gateway_name" {
  value = aws_api_gateway_rest_api.api.name
}

output "events_queue_name" {
  value = aws_sqs_queue.events.name
}

output "events_queue" {
  value = {
    arn  = aws_sqs_queue.events.arn
    url  = aws_sqs_queue.events.url
    name = aws_sqs_queue.events.name
  }
}

output "events_dlq_name" {
  value = aws_sqs_queue.events_dlq.name
}

output "monitoring_topic_arn" {
  value = aws_sns_topic.monitoring.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.api.name
}

output "mcp_distribution" {
  description = "What the MCP host's Route 53 alias points at."
  value = {
    domain_name    = aws_cloudfront_distribution.mcp.domain_name
    hosted_zone_id = aws_cloudfront_distribution.mcp.hosted_zone_id
  }
}

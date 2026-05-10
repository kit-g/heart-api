output "api" {
  value = {
    domain_name = "${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com"
    stage_path  = aws_api_gateway_stage.v1.stage_name
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

output "events_dlq_name" {
  value = aws_sqs_queue.events_dlq.name
}

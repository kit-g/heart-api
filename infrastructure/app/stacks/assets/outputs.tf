output "function_name" {
  value = aws_lambda_function.assets.function_name
}

output "events_queue" {
  value = {
    arn  = aws_sqs_queue.events.arn
    url  = aws_sqs_queue.events.url
    name = aws_sqs_queue.events.name
  }
}

output "events_dlq" {
  value = {
    arn  = aws_sqs_queue.events_dlq.arn
    name = aws_sqs_queue.events_dlq.name
  }
}

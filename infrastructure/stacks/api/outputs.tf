output "api" {
  value = {
    domain_name = "${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com"
    stage_path  = aws_api_gateway_stage.v1.stage_name
  }
}

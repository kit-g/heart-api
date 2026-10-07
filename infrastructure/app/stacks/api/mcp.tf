# The MCP host (mcp.heart-of.me): the API's own binary with only the MCP router
# wired (HEART_SURFACE=mcp), in a function of its own so assistants' traffic has
# its own concurrency and never queues behind the app's. The deploy ships the
# same zip to both functions. The API keeps serving /v1/mcp for personal tokens.

# CloudFront proves itself to the public function URL with this header; the
# function refuses requests without it. Origin access control would sign
# instead, but it needs signed POST bodies, which no MCP client sends.
resource "random_password" "mcp_origin" {
  length  = 48
  special = false
}

resource "aws_cloudwatch_log_group" "mcp" {
  name              = "/aws/lambda/${var.name_prefix}-mcp"
  retention_in_days = var.log_retention
}

resource "aws_lambda_function" "mcp" {
  function_name    = "${var.name_prefix}-mcp"
  description      = "Part of Heart: the MCP server, on its own host"
  role             = module.api_role.role_arn
  runtime          = "provided.al2023"
  architectures    = ["arm64"]
  handler          = "app.handler"
  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256
  memory_size      = 512
  timeout          = 30
  depends_on       = [aws_cloudwatch_log_group.mcp]

  # Its instances hold database connections too, from the same pool as the
  # API's: see var.mcp_concurrency.
  reserved_concurrent_executions = coalesce(var.mcp_concurrency, -1)

  layers = [
    "arn:aws:lambda:${var.region}:753240598075:layer:LambdaAdapterLayerArm64:25"
  ]

  environment {
    variables = merge(local.lambda_environment, {
      HEART_SURFACE     = "mcp"
      MCP_ORIGIN_SECRET = random_password.mcp_origin.result
      # served at the root of its own host, not under /v1
      AWS_LWA_REMOVE_BASE_PATH = ""
      # a response can be a per-request stream (progress, then the result)
      AWS_LWA_INVOKE_MODE = "response_stream"
    })
  }

  lifecycle {
    # Real code is shipped by CI (deploy-api.yml), as for the API.
    ignore_changes = [filename, source_code_hash]
  }
}

# Public, but useless without the origin header CloudFront adds (above). Every
# MCP call also carries a bearer token, and the function's reserved
# concurrency bounds what a flood can cost.
resource "aws_lambda_function_url" "mcp" {
  function_name      = aws_lambda_function.mcp.function_name
  authorization_type = "NONE"
  invoke_mode        = "RESPONSE_STREAM"
}

# The console attaches this for a NONE URL; through the API it has to be said.
resource "aws_lambda_permission" "mcp_url" {
  statement_id           = "FunctionUrlPublic"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.mcp.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# Every viewer header but Host, Authorization included: a function URL answers
# only to its own host name, and the server needs the bearer token. Nothing is
# cached, so no response can reach another caller.
data "aws_cloudfront_origin_request_policy" "all_but_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "mcp" {
  enabled         = true
  comment         = "Heart MCP host"
  aliases         = var.mcp_domain == null ? [] : [var.mcp_domain.name]
  price_class     = "PriceClass_100"
  is_ipv6_enabled = true

  origin {
    domain_name = trimsuffix(trimprefix(aws_lambda_function_url.mcp.function_url, "https://"), "/")
    origin_id   = "mcp"

    custom_header {
      name  = "x-heart-origin"
      value = random_password.mcp_origin.result
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = "mcp"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_but_host.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Without a domain the distribution serves its own *.cloudfront.net name.
  viewer_certificate {
    cloudfront_default_certificate = var.mcp_domain == null
    acm_certificate_arn            = var.mcp_domain == null ? null : var.mcp_domain.certificate_arn
    ssl_support_method             = var.mcp_domain == null ? null : "sni-only"
    minimum_protocol_version       = var.mcp_domain == null ? "TLSv1" : "TLSv1.2_2021"
  }
}

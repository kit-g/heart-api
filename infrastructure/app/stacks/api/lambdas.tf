# Both functions run the same binary with the same environment; the MCP host
# adds only HEART_SURFACE (mcp.tf).
locals {
  lambda_environment = {
    ACCOUNT_DELETION_OFFSET_DAYS = tostring(var.account_deletion_offset_days)
    ALLOWED_ORIGINS              = join(",", var.allowed_origins)
    # OAuth is on only where both are known: the issuer, and the API's public
    # address, which the issuer's metadata names as its endpoints.
    API_PUBLIC_URL            = var.custom_domain == null ? "" : "https://${var.custom_domain.name}/v1"
    APPLE_CLIENT_IDS          = join(",", var.apple_sign_in.client_ids)
    APPLE_KEY_ID              = var.apple_sign_in.key_id
    APPLE_PRIVATE_KEY         = var.apple_sign_in.private_key
    APPLE_TEAM_ID             = var.apple_sign_in.team_id
    AWS_LAMBDA_EXEC_WRAPPER   = "/opt/bootstrap"
    AWS_LWA_PORT              = 8080
    AWS_LWA_REMOVE_BASE_PATH  = "/v1"
    CONTENT_BUCKET            = var.content_bucket.bucket
    ENV                       = var.environment
    EVENTS_QUEUE_ARN          = aws_sqs_queue.events.arn
    EVENTS_QUEUE_URL          = aws_sqs_queue.events.url
    EVENTS_DLQ                = aws_sqs_queue.events_dlq.url
    FIREBASE_EVENTS_QUEUE_URL = var.firebase_events_queue.url
    FIREBASE_PROJECT_ID       = var.firebase_project_id
    LOG_LEVEL                 = "ALL"
    # the MCP host's address, once it has a domain; until then OAuth names the
    # API's own /mcp
    MCP_RESOURCE         = var.mcp_domain == null ? "" : "https://${var.mcp_domain.name}"
    MEDIA_DISTRIBUTION   = var.media_distribution
    MIN_APP_VERSION      = "1.0.0"
    MONITORING_TOPIC_ARN = aws_sns_topic.monitoring.arn
    PG_DATABASE          = var.database.database
    PG_HOST              = var.database.host
    PG_PASSWORD          = var.database.password
    PG_PORT              = var.database.port
    PG_USER              = var.database.user
    REGION               = var.region
    SCHEDULE_GROUP       = aws_scheduler_schedule_group.accounts.name
    SCHEDULER_ROLE_ARN   = aws_iam_role.scheduler.arn
    SITE_ORIGIN          = var.site_origin == null ? "" : var.site_origin
    SUPPORTED_LOCALES    = "en,en_CA,ru,es,es_ES,fr,fr_CA"
  }
}

resource "aws_lambda_function" "api" {
  function_name    = var.name_prefix
  description      = "Part of Heart: API function"
  role             = module.api_role.role_arn
  runtime          = "provided.al2023"
  architectures    = ["arm64"]
  handler          = "app.handler"
  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256
  memory_size      = 512
  timeout          = 120
  depends_on       = [aws_cloudwatch_log_group.api]

  # Each instance holds one database connection, so instances past the
  # pooler's size fail to connect. Reserving the cap also keeps the other
  # functions' share of the account; -1 is no reservation.
  reserved_concurrent_executions = coalesce(var.api_concurrency, -1)

  layers = [
    "arn:aws:lambda:${var.region}:753240598075:layer:LambdaAdapterLayerArm64:25"
  ]

  environment {
    variables = local.lambda_environment
  }

  lifecycle {
    # Real code is shipped by CI (deploy-api.yml). TF only manages the
    # function's structure (runtime, role, env, wiring).
    ignore_changes = [filename, source_code_hash]
  }
}

resource "aws_lambda_function" "api" {
  function_name    = var.name_prefix
  description      = "Part of Heart: API function"
  role             = module.api_role.role_arn
  runtime          = "provided.al2023"
  architectures    = ["arm64"]
  handler          = "app.handler"
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  memory_size      = 512
  timeout          = 120
  depends_on       = [aws_cloudwatch_log_group.api]

  layers = [
    "arn:aws:lambda:${var.region}:753240598075:layer:LambdaAdapterLayerArm64:25"
  ]

  environment {
    variables = {
      AWS_LAMBDA_EXEC_WRAPPER  = "/opt/bootstrap"
      AWS_LWA_PORT             = 8080
      AWS_LWA_REMOVE_BASE_PATH = "/v2"
      ENV                      = "dev"
      CONTENT_BUCKET           = var.content_bucket.bucket
      FIREBASE_PROJECT_ID      = var.firebase_project_id
      LOG_LEVEL                = "ALL"
      MEDIA_DISTRIBUTION       = "dev.media.heart-of.me"
      MONITORING_TOPIC         = aws_sns_topic.monitoring.name
      MIN_APP_VERSION          = "1.0.0"
      REGION                   = var.region
      SUPPORTED_LOCALES        = "en,en_CA,ru"
      PG_DATABASE              = var.database.database
      PG_HOST                  = var.database.host
      PG_PASSWORD              = var.database.password
      PG_PORT                  = var.database.port
      PG_USER                  = var.database.user
      EVENTS_DLQ               = aws_sqs_queue.events_dlq.url
    }
  }
}

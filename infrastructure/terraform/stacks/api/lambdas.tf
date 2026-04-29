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
      EXERCISE_BUCKET          = var.content_bucket.bucket
      FIREBASE_PROJECT_ID      = var.firebase_project_id
      LOG_LEVEL                = "ALL"
      MEDIA_DISTRIBUTION       = "https://dev.media.heart-of.me"
      MONITORING_TOPIC         = aws_sns_topic.monitoring.name
      MIN_APP_VERSION          = "1.0.0"
      REGION                   = var.region
      SUPPORTED_LOCALES        = "en,en_CA,ru"
      PG_DATABASE              = local.rds_creds.Database
      PG_HOST                  = local.rds_creds.Host
      PG_PASSWORD              = local.rds_creds.Password
      PG_PORT                  = local.rds_creds.Port
      PG_USER                  = local.rds_creds.User
    }
  }
}

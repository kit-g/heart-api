output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}

output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "firebase_web_config" {
  description = "The web app's Firebase config, for site/connect/<env>.js (with authDomain set to the site's own host)."
  value = {
    apiKey    = data.google_firebase_web_app_config.web.api_key
    projectId = var.firebase_project_config.project_id
    appId     = google_firebase_web_app.web.app_id
  }
}

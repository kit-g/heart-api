output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}

output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

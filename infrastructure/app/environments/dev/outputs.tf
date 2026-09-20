output "media_distribution_id" {
  value       = module.cdn.media_distribution.id
  description = "Media CloudFront distribution id — feeds the global stack's media_distribution_id (issue #65)."
}

output "api_custom_domain" {
  value       = module.api.custom_domain
  description = "API Gateway custom domain. `target` is what the `dns` root module's <env>_api_domain_name variable takes, since that module holds its own state and is applied separately."
}

output "media_distribution_id" {
  value       = module.cdn.media_distribution.id
  description = "Media CloudFront distribution id — feeds the global stack's media_distribution_id (issue #65)."
}

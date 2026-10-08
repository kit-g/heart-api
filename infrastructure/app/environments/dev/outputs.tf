output "media_distribution_id" {
  value       = module.cdn.media_distribution.id
  description = "Media CloudFront distribution id — feeds the global stack's media_distribution_id (issue #65)."
}

output "name_servers" {
  value       = aws_route53_zone.dev.name_servers
  description = "dev's four name servers: what the apex delegates dev.heart-of.me to, by hand, since that state is in another account."
}

output "media_distribution_id" {
  value       = module.cdn.media_distribution.id
  description = "Media CloudFront distribution id — feeds the global stack's media_distribution_id (issue #65)."
}

output "name_servers" {
  value       = aws_route53_zone.apex.name_servers
  description = "The apex zone's name servers: what the registrar points at."
}

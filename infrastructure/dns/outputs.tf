output "zone_id" {
  value = aws_route53_zone.apex.zone_id
}

output "name_servers" {
  value       = aws_route53_zone.apex.name_servers
  description = "Authoritative NS records for the apex zone — what the registrar should point at."
}

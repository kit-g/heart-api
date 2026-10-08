# dev's names moved to the dev account's own zone (heart-api#142); from here
# the whole `dev` subtree is a delegation. Empty until that zone exists, so this
# root stays appliable before it: the same `""`-means-off switch the API alias
# had while its domain name did not exist yet.
resource "aws_route53_record" "dev_delegation" {
  count = length(var.dev_name_servers) == 0 ? 0 : 1

  zone_id = aws_route53_zone.apex.id
  name    = "dev.${var.apex_domain}"
  type    = "NS"
  ttl     = 172800
  records = var.dev_name_servers
}

# dev's names, each a zone of its own in this account, delegated from the apex
# in prod. `dev.api` and `dev.media` are siblings of `dev`, not children, so one
# `dev` zone could not hold them (heart-api#142); three small zones keep the
# names installed dev builds and the site already use. The zones share one
# delegation set, so the apex delegates all three to the same four name servers:
# the `name_servers` output, which prod's `dev_name_servers` takes.

locals {
  web_host   = "dev.heart-of.me"
  www_host   = "www.dev.heart-of.me"
  api_host   = "dev.api.heart-of.me"
  media_host = "dev.media.heart-of.me"

  zones = toset([local.web_host, local.api_host, local.media_host])

  aliases = {
    for name, record in {
      (local.web_host)   = { zone = local.web_host, target = module.cdn.web_distribution }
      (local.www_host)   = { zone = local.web_host, target = module.cdn.web_distribution }
      (local.api_host)   = { zone = local.api_host, target = module.api.custom_domain }
      (local.media_host) = { zone = local.media_host, target = module.cdn.media_distribution }
      } : name => {
      zone           = record.zone
      domain_name    = record.target.domain_name
      hosted_zone_id = record.target.hosted_zone_id
    }
  }
}

resource "aws_route53_delegation_set" "dev" {
  reference_name = "heart-dev"
}

resource "aws_route53_zone" "dev" {
  for_each = local.zones

  name              = each.key
  comment           = "${each.key}: delegated from the apex in prod"
  delegation_set_id = aws_route53_delegation_set.dev.id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "alias" {
  for_each = local.aliases

  zone_id = aws_route53_zone.dev[each.value.zone].zone_id
  name    = each.key
  type    = "A"

  alias {
    name                   = each.value.domain_name
    zone_id                = each.value.hosted_zone_id
    evaluate_target_health = false
  }
}

# region: Firebase mail from dev.heart-of.me: SPF, project verification, DKIM
resource "aws_route53_record" "firebase_txt" {
  zone_id = aws_route53_zone.dev[local.web_host].zone_id
  name    = local.web_host
  type    = "TXT"
  ttl     = 14400
  records = [
    "v=spf1 include:_spf.firebasemail.com ~all",
    "firebase=${var.firebase_project_id}",
  ]
}

resource "aws_route53_record" "firebase_dkim" {
  for_each = { firebase1 = "dkim1", firebase2 = "dkim2" }

  zone_id = aws_route53_zone.dev[local.web_host].zone_id
  name    = "${each.key}._domainkey.${local.web_host}"
  type    = "CNAME"
  ttl     = 14400
  records = ["mail-dev-heart--of-me.${each.value}._domainkey.firebasemail.com."]
}
# endregion

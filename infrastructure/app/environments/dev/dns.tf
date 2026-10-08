# dev's zone, delegated from the apex in prod. Every dev name is under it:
# `api.dev` and `media.dev` rather than the `dev.api` and `dev.media` they
# were, which were siblings of `dev` and could not have been delegated with it
# (heart-api#142). The zone's `name_servers` output is what prod's
# `dev_name_servers` takes.

locals {
  web_host   = "dev.heart-of.me"
  www_host   = "www.dev.heart-of.me"
  api_host   = "api.dev.heart-of.me"
  media_host = "media.dev.heart-of.me"

  aliases = {
    for name, target in {
      (local.web_host)   = module.cdn.web_distribution
      (local.www_host)   = module.cdn.web_distribution
      (local.api_host)   = module.api.custom_domain
      (local.media_host) = module.cdn.media_distribution
      } : name => {
      domain_name    = target.domain_name
      hosted_zone_id = target.hosted_zone_id
    }
  }
}

resource "aws_route53_zone" "dev" {
  name    = local.web_host
  comment = "${local.web_host}: delegated from the apex in prod"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "alias" {
  for_each = local.aliases

  zone_id = aws_route53_zone.dev.zone_id
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
  zone_id = aws_route53_zone.dev.zone_id
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

  zone_id = aws_route53_zone.dev.zone_id
  name    = "${each.key}._domainkey.${local.web_host}"
  type    = "CNAME"
  ttl     = 14400
  records = ["mail-dev-heart--of-me.${each.value}._domainkey.firebasemail.com."]
}
# endregion

# The apex zone: prod's names, the domain's mail, and the delegation of dev's
# zone. The registrar (Gandi) points at the `name_servers` output.

locals {
  apex_domain = "heart-of.me"
  www_host    = "www.heart-of.me"
  api_host    = "api.heart-of.me"
  media_host  = "media.heart-of.me"
  mcp_host    = "mcp.heart-of.me"

  aliases = {
    for name, target in {
      (local.apex_domain) = module.cdn.web_distribution
      (local.www_host)    = module.cdn.web_distribution
      (local.api_host)    = module.api.custom_domain
      (local.media_host)  = module.cdn.media_distribution
      (local.mcp_host)    = module.api.mcp_distribution
      } : name => {
      domain_name    = target.domain_name
      hosted_zone_id = target.hosted_zone_id
    }
  }

  # Every dev name is under this one, in the dev account.
  dev_zone = "dev.heart-of.me"
}

resource "aws_route53_zone" "apex" {
  name    = local.apex_domain
  comment = "${local.apex_domain} hosted zone"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "alias" {
  for_each = local.aliases

  zone_id = aws_route53_zone.apex.zone_id
  name    = each.key
  type    = "A"

  alias {
    name                   = each.value.domain_name
    zone_id                = each.value.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "delegation" {
  zone_id = aws_route53_zone.apex.zone_id
  name    = local.dev_zone
  type    = "NS"
  ttl     = 172800
  records = var.dev_name_servers
}

# region: mail at the apex (improvmx forwarding, Firebase sending), and the
# site verifications that share the apex TXT
resource "aws_route53_record" "apex_mx" {
  zone_id = aws_route53_zone.apex.zone_id
  name    = local.apex_domain
  type    = "MX"
  ttl     = 14400
  records = [
    "10 mx1.improvmx.com",
    "20 mx2.improvmx.com",
  ]
}

resource "aws_route53_record" "apex_txt" {
  zone_id = aws_route53_zone.apex.zone_id
  name    = local.apex_domain
  type    = "TXT"
  ttl     = 14400
  records = [
    "v=spf1 include:spf.improvmx.com ~all",
    "v=spf1 include:_spf.firebasemail.com ~all",
    "google-site-verification=r5-Cw1hkYWb3xDhuBaLOv_dNujEY3h-w512B0KtSUSk",
    "firebase=${var.firebase_project_id}",
  ]
}

resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.apex.zone_id
  name    = "_dmarc.${local.apex_domain}"
  type    = "TXT"
  ttl     = 3600
  records = ["v=DMARC1; p=none; rua=mailto:info@heart-of.me"]
}

resource "aws_route53_record" "firebase_dkim" {
  for_each = { firebase1 = "dkim1", firebase2 = "dkim2" }

  zone_id = aws_route53_zone.apex.zone_id
  name    = "${each.key}._domainkey.${local.apex_domain}"
  type    = "CNAME"
  ttl     = 14400
  records = ["mail-heart--of-me.${each.value}._domainkey.firebasemail.com."]
}
# endregion

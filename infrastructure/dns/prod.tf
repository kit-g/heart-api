resource "aws_route53_record" "prod_media" {
  zone_id = aws_route53_zone.apex.id
  name    = "media.${var.apex_domain}"
  type    = "A"

  alias {
    name                   = var.prod_media_distribution_domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "web" {
  zone_id = aws_route53_zone.apex.id
  name    = var.apex_domain
  type    = "A"

  alias {
    name                   = var.prod_web_distribution_domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.apex.id
  name    = "www.${var.apex_domain}"
  type    = "A"

  alias {
    name                   = var.prod_web_distribution_domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}

# region: Firebase validation
resource "aws_route53_record" "dkim_1" {
  zone_id = aws_route53_zone.apex.id
  name    = "firebase1._domainkey.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 14400
  records = ["mail-heart--of-me.dkim1._domainkey.firebasemail.com."]
}

resource "aws_route53_record" "dkim_2" {
  zone_id = aws_route53_zone.apex.id
  name    = "firebase2._domainkey.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 14400
  records = ["mail-heart--of-me.dkim2._domainkey.firebasemail.com."]
}
# endregion

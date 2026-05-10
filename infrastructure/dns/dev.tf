# Records under dev.heart-of.me. They live in the apex zone today; once a
# prod account exists they'll move into a delegated dev.heart-of.me subzone.

# ------ Web aliases ------

resource "aws_route53_record" "dev_web" {
  zone_id = aws_route53_zone.apex.id
  name    = "dev.${var.apex_domain}"
  type    = "A"

  alias {
    name                   = var.web_distribution_domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "dev_www" {
  zone_id = aws_route53_zone.apex.id
  name    = "www.dev.${var.apex_domain}"
  type    = "A"

  alias {
    name                   = var.web_distribution_domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "dev_media" {
  zone_id = aws_route53_zone.apex.id
  name    = "dev.media.${var.apex_domain}"
  type    = "A"

  alias {
    name                   = var.media_distribution_domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}

# ------ Firebase email DKIM + SPF + project verification ------

resource "aws_route53_record" "dev_dkim_1" {
  zone_id = aws_route53_zone.apex.id
  name    = "firebase1._domainkey.dev.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 14400
  records = ["mail-dev-heart--of-me.dkim1._domainkey.firebasemail.com."]
}

resource "aws_route53_record" "dev_dkim_2" {
  zone_id = aws_route53_zone.apex.id
  name    = "firebase2._domainkey.dev.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 14400
  records = ["mail-dev-heart--of-me.dkim2._domainkey.firebasemail.com."]
}

resource "aws_route53_record" "dev_txt" {
  zone_id = aws_route53_zone.apex.id
  name    = "dev.${var.apex_domain}"
  type    = "TXT"
  ttl     = 14400
  records = [
    "v=spf1 include:_spf.firebasemail.com ~all",
    "firebase=${var.firebase_dev_project_id}",
  ]
}

# ACM cert validation CNAMEs. Cert lifecycle is managed outside TF — these
# records are kept in sync manually when issuing/rotating certs. Each one is
# a one-time validation token; ACM stops needing them once issued, but
# leaving them in place is the standard practice.

resource "aws_route53_record" "acm_dev_apex" {
  zone_id = aws_route53_zone.apex.id
  name    = "_b7feebaf597a5b3dfa112fb63ad76a40.dev.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 14400
  records = ["_f3c60a3d8cc31b91fd49ea5e969c15f8.xlfgrmvvlj.acm-validations.aws."]
}

resource "aws_route53_record" "acm_dev_www" {
  zone_id = aws_route53_zone.apex.id
  name    = "_323f7b7de154eed3a1faa0f26192a320.www.dev.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 14400
  records = ["_2b937ce14a76052f45b0f5e3e792251d.xlfgrmvvlj.acm-validations.aws."]
}

resource "aws_route53_record" "acm_dev_media" {
  zone_id = aws_route53_zone.apex.id
  name    = "_a66f9b14b2fe79100de8da2794bbda3e.dev.media.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 14400
  records = ["_1d9796af82610f64321c6d4ffc014691.xlfgrmvvlj.acm-validations.aws."]
}

resource "aws_route53_record" "acm_media_dev" {
  zone_id = aws_route53_zone.apex.id
  name    = "_1c6dd197c647ba02cd8dda34a34d7744.media.dev.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 300
  records = ["_26e7f763e4573a5ec13911b32027b655.jkddzztszm.acm-validations.aws."]
}

resource "aws_route53_record" "acm_media_prod" {
  zone_id = aws_route53_zone.apex.id
  name    = "_ec65c8830e75069be3ce96cacab5afe4.media.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 300
  records = ["_d84ba691b4ceafb2ca9248fd25fa8df7.jkddzztszm.acm-validations.aws."]
}

resource "aws_route53_record" "acm_prod_apex" {
  zone_id = aws_route53_zone.apex.id
  name    = "_f0a88837c3d8ad38ffe1fdbad85d8b8d.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 14400
  records = ["_76f758a8ba4fbacd272921ed5e1746ef.jkddzztszm.acm-validations.aws."]
}

resource "aws_route53_record" "acm_prod_www" {
  zone_id = aws_route53_zone.apex.id
  name    = "_b393d9db14d89d75a1c6955508d9c682.www.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 14400
  records = ["_a8919cbb2244336f7d0a8fdc516be252.jkddzztszm.acm-validations.aws."]
}
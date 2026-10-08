# ACM cert validation CNAMEs. Cert lifecycle is managed outside TF — these
# records are kept in sync manually when issuing/rotating certs. Each one is
# a one-time validation token; ACM stops needing them once issued, but
# leaving them in place is the standard practice.

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

# The API certificate is the only one in this file issued in ca-central-1,
# not us-east-1: a REGIONAL API Gateway domain name will not take a certificate
# from anywhere but its own region.

resource "aws_route53_record" "acm_prod_api" {
  zone_id = aws_route53_zone.apex.id
  name    = "_3523e482d0ff62c690b0841ed092802a.api.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 300
  records = ["_0f0e9bc3701b654928736e57354c362a.wzccmgtwzk.acm-validations.aws."]
}

# CloudFront takes certificates only from us-east-1, so the MCP host's is there.
resource "aws_route53_record" "acm_prod_mcp" {
  zone_id = aws_route53_zone.apex.id
  name    = "_18c6874c203eee78de4873d6b8417b5e.mcp.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 300
  records = ["_5a474671b16c00ebcdbd860e14dc6bac.wzccmgtwzk.acm-validations.aws."]
}

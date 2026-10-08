# The certificates, issued and validated here, in dev's zone. CloudFront's are
# in us-east-1; the API's is regional, like its domain name.

module "web_certificate" {
  source    = "../../modules/certificate"
  providers = { aws = aws.us_east_1 }

  domain_name               = local.web_host
  subject_alternative_names = [local.www_host]
  zone_id                   = aws_route53_zone.dev.zone_id
}

module "media_certificate" {
  source    = "../../modules/certificate"
  providers = { aws = aws.us_east_1 }

  domain_name = local.media_host
  zone_id     = aws_route53_zone.dev.zone_id
}

module "api_certificate" {
  source = "../../modules/certificate"

  domain_name = local.api_host
  zone_id     = aws_route53_zone.dev.zone_id
}

# Issued by hand before the environment managed it, and the one certificate
# whose names survived the rename. Imported rather than reissued, so the web
# distribution keeps the certificate it holds; ACM asks for the same validation
# record either way.
import {
  to = module.web_certificate.aws_acm_certificate.this
  id = "arn:aws:acm:us-east-1:583168578067:certificate/2ac33117-c985-4f4d-a382-d2c8bad1766a"
}

module "mcp_certificate" {
  source    = "../../modules/certificate"
  providers = { aws = aws.us_east_1 }

  domain_name = local.mcp_host
  zone_id     = aws_route53_zone.dev.zone_id
}

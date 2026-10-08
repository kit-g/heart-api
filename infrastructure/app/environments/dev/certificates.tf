# The certificates, issued and validated here, each in its own name's zone.
# CloudFront's are in us-east-1; the API's is regional, like its domain name.

module "web_certificate" {
  source    = "../../modules/certificate"
  providers = { aws = aws.us_east_1 }

  domain_name               = local.web_host
  subject_alternative_names = [local.www_host]
  zone_id                   = aws_route53_zone.dev[local.web_host].zone_id
}

module "media_certificate" {
  source    = "../../modules/certificate"
  providers = { aws = aws.us_east_1 }

  domain_name = local.media_host
  zone_id     = aws_route53_zone.dev[local.media_host].zone_id
}

module "api_certificate" {
  source = "../../modules/certificate"

  domain_name = local.api_host
  zone_id     = aws_route53_zone.dev[local.api_host].zone_id
}

# Issued by hand before the environment managed them. Imported rather than
# reissued, so the distributions and the domain name keep the certificate they
# hold; ACM asks for the same validation record either way.
import {
  to = module.web_certificate.aws_acm_certificate.this
  id = "arn:aws:acm:us-east-1:583168578067:certificate/2ac33117-c985-4f4d-a382-d2c8bad1766a"
}

import {
  to = module.media_certificate.aws_acm_certificate.this
  id = "arn:aws:acm:us-east-1:583168578067:certificate/297c34bc-7a74-4cb1-82c4-71bfe0114eb7"
}

import {
  to = module.api_certificate.aws_acm_certificate.this
  id = "arn:aws:acm:ca-central-1:583168578067:certificate/43e5a2aa-7c62-4fa4-a137-9b35df1f47b6"
}

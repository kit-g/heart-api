# The certificates, issued and validated here, in the apex zone. CloudFront's
# are in us-east-1; the API's is regional, like its domain name.

module "web_certificate" {
  source    = "../../modules/certificate"
  providers = { aws = aws.us_east_1 }

  domain_name               = local.apex_domain
  subject_alternative_names = [local.www_host]
  zone_id                   = aws_route53_zone.apex.zone_id
}

module "media_certificate" {
  source    = "../../modules/certificate"
  providers = { aws = aws.us_east_1 }

  domain_name = local.media_host
  zone_id     = aws_route53_zone.apex.zone_id
}

module "mcp_certificate" {
  source    = "../../modules/certificate"
  providers = { aws = aws.us_east_1 }

  domain_name = local.mcp_host
  zone_id     = aws_route53_zone.apex.zone_id
}

module "api_certificate" {
  source = "../../modules/certificate"

  domain_name = local.api_host
  zone_id     = aws_route53_zone.apex.zone_id
}

# Issued by hand before the environment managed them. Imported rather than
# reissued, so the distributions and the domain name keep the certificate they
# hold; ACM asks for the same validation record either way.
import {
  to = module.web_certificate.aws_acm_certificate.this
  id = "arn:aws:acm:us-east-1:922419543441:certificate/60a653e8-c734-4d9a-bd92-747e9f4e994a"
}

import {
  to = module.media_certificate.aws_acm_certificate.this
  id = "arn:aws:acm:us-east-1:922419543441:certificate/a91ae5f9-d156-465b-9ea4-d3564a7175d6"
}

import {
  to = module.mcp_certificate.aws_acm_certificate.this
  id = "arn:aws:acm:us-east-1:922419543441:certificate/45ae4eb4-8cc9-40af-a9e2-9b6f06c8084a"
}

import {
  to = module.api_certificate.aws_acm_certificate.this
  id = "arn:aws:acm:ca-central-1:922419543441:certificate/f5a9b784-19a5-4ef6-b284-be9fc51b79dd"
}

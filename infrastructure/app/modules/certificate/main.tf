# One DNS-validated certificate and the record that validates it, in a single
# apply: ACM names the record once the request exists, the record goes into
# the zone, and the validation waits for issuance before handing the ARN on.

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  # A change of names is a new certificate. The replacement has to be issued
  # and attached before the old one goes, or the distribution loses its TLS
  # in between.
  lifecycle {
    create_before_destroy = true
  }
}

# Keyed by the names from the configuration, not by what ACM reports: the set of
# records is then known at plan time, and only their contents arrive with the
# request.
locals {
  validation = {
    for option in aws_acm_certificate.this.domain_validation_options : option.domain_name => option
  }
}

resource "aws_route53_record" "validation" {
  for_each = toset(concat([var.domain_name], var.subject_alternative_names))

  zone_id = var.zone_id
  name    = local.validation[each.key].resource_record_name
  type    = local.validation[each.key].resource_record_type
  ttl     = 300
  records = [local.validation[each.key].resource_record_value]
}

# Renewal reads the same record again each year, which is why the records
# stay after issuance rather than being torn down.
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

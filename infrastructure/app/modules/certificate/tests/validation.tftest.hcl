# Tests for the certificate module.
#
# Run from this module's directory:  terraform init && terraform test
#
# Mocked provider, so nothing reaches AWS. The validation options are what ACM
# returns after the request, so the certificate is overridden to a known set
# and the test checks that every name on it gets its record and that the
# validation waits on exactly those records.

mock_provider "aws" {}

variables {
  domain_name               = "heart-of.me"
  subject_alternative_names = ["www.heart-of.me"]
  zone_id                   = "Z0000000000000000000"
}

# apply, not plan, so the overridden options are known values the records can
# be keyed on. With the provider mocked, apply touches nothing real.
run "one_record_per_name" {
  command = apply

  override_resource {
    target = aws_acm_certificate.this
    values = {
      arn = "arn:aws:acm:us-east-1:000000000000:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [
        {
          domain_name           = "heart-of.me"
          resource_record_name  = "_a.heart-of.me."
          resource_record_type  = "CNAME"
          resource_record_value = "_1.acm-validations.aws."
        },
        {
          domain_name           = "www.heart-of.me"
          resource_record_name  = "_b.www.heart-of.me."
          resource_record_type  = "CNAME"
          resource_record_value = "_2.acm-validations.aws."
        },
      ]
    }
  }

  assert {
    condition     = keys(aws_route53_record.validation) == ["heart-of.me", "www.heart-of.me"]
    error_message = "One validation record per name on the certificate, keyed by that name"
  }

  assert {
    condition     = aws_route53_record.validation["www.heart-of.me"].name == "_b.www.heart-of.me."
    error_message = "The record carries the name ACM asked for"
  }

  assert {
    condition     = aws_route53_record.validation["www.heart-of.me"].records == toset(["_2.acm-validations.aws."])
    error_message = "The record carries the value ACM asked for"
  }

  assert {
    condition     = length(aws_acm_certificate_validation.this.validation_record_fqdns) == 2
    error_message = "Validation waits on every record"
  }

  assert {
    condition     = output.arn == "arn:aws:acm:us-east-1:000000000000:certificate/00000000-0000-0000-0000-000000000000"
    error_message = "The ARN handed on is the certificate's"
  }
}

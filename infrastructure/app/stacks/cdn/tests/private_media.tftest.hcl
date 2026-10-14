mock_provider "aws" {
  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:function/test"
    }
  }
}

variables {
  media_distribution_aliases         = ["media.example.com"]
  web_distribution_aliases           = ["example.com"]
  firebase_auth_domain               = "example.firebaseapp.com"
  media_distribution_ssl_certificate = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  web_distribution_ssl_certificate   = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  content_bucket = {
    id                          = "content"
    arn                         = "arn:aws:s3:::content"
    bucket_regional_domain_name = "content.s3.ca-central-1.amazonaws.com"
  }
  static_bucket = {
    id                          = "static"
    arn                         = "arn:aws:s3:::static"
    bucket_regional_domain_name = "static.s3.ca-central-1.amazonaws.com"
  }
}

# Mocked apply resolves generated ARNs; no resources or network calls exist.
run "private_prefixes_are_denied_at_the_origin" {
  command = apply

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.content_cloudfront_access.policy).Statement :
      statement.Effect == "Deny" && try(
        statement.Principal.Service == "cloudfront.amazonaws.com" &&
        alltrue([
          for prefix in ["imports", "exports", "uploads", "exercise-uploads"] :
          contains(statement.Resource, "arn:aws:s3:::content/${prefix}/*")
        ]),
        false,
      )
    ])
    error_message = "S3 must refuse CloudFront reads of private prefixes."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.content_cloudfront_access.policy).Statement :
      statement.Effect == "Allow" && statement.Resource == "arn:aws:s3:::content/*"
    ])
    error_message = "Existing public content must retain its CDN access."
  }
}

resource "aws_cloudfront_origin_access_control" "heart" {
  name                              = "heart-oac"
  description                       = "OAC for the Heart app resources"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "content_cloudfront_access" {
  bucket = var.content_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${var.content_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.media.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "static_cloudfront_access" {
  bucket = var.static_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${var.static_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.web.arn
          }
        }
      }
    ]
  })
}

locals {
  content_origin                = "content-bucket"
  static_origin                 = "static-bucket"
  firebase_origin               = "firebase-auth"
  caching_optimized             = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CloudFront managed cache policy ID
  caching_disabled              = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CloudFront managed cache policy ID
  all_viewer_except_host_header = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # CloudFront managed origin request policy ID for AllViewerExceptHostHeader, needed to forward Firebase auth requests to the app, with query params
}

locals {
  media_cors_enabled = length(var.media_cors_origins) > 0

  # OPTIONS only where something will answer it. CloudFront refuses a method a
  # behavior does not allow before any policy is consulted, and S3 has no CORS
  # configuration to answer a forwarded preflight with.
  media_methods = local.media_cors_enabled ? ["GET", "HEAD", "OPTIONS"] : ["GET", "HEAD"]
}

# Browser access to the media distribution. CloudFront answers the preflight
# itself and adds these after the cache lookup, so `Origin` never enters the
# cache key: every viewer shares one cached copy of an object with the app,
# which sends no `Origin` at all. Configuring CORS on the bucket instead would
# mean keying the cache on `Origin` to stay correct, and paying for it on the
# traffic that is almost all of it.
resource "aws_cloudfront_response_headers_policy" "media_cors" {
  count = local.media_cors_enabled ? 1 : 0

  name    = "HeartMediaCors"
  comment = "Browser access to media assets, per environment"

  cors_config {
    access_control_allow_credentials = false
    origin_override                  = true
    access_control_max_age_sec       = 3600

    access_control_allow_origins {
      items = var.media_cors_origins
    }

    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS"]
    }

    # None of these is CORS-safelisted, so the request carrying one preflights:
    # `if-none-match` on the exercise library's revalidation, `cache-control`
    # and `x-app-version` on an image fetch.
    access_control_allow_headers {
      items = ["accept", "cache-control", "if-none-match", "x-app-version"]
    }

    # `etag` is not a safelisted *response* header, so without this the client
    # reads null where the library's ETag should be, never sends
    # `If-None-Match`, and re-downloads the whole catalog on every load.
    access_control_expose_headers {
      items = ["etag"]
    }
  }
}

resource "aws_cloudfront_cache_policy" "media" {
  name        = "HeartMediaCacheWithQuery"
  comment     = "Copy of CachingOptimized policy, except it allows the 'v' query param"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "whitelist"

      query_strings { items = ["v"] }
    }

    cookies_config {
      cookie_behavior = "none"
    }
  }
}

resource "aws_cloudfront_distribution" "media" {
  enabled = true
  comment = "Heart of yours, media assets"

  origin {
    domain_name              = var.content_bucket.bucket_regional_domain_name
    origin_id                = local.content_origin
    origin_access_control_id = aws_cloudfront_origin_access_control.heart.id
    # empty, as per
    # https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-cloudfront-distribution-s3originconfig.html#cfn-cloudfront-distribution-s3originconfig-originaccessidentity
    origin_path = ""
  }

  default_cache_behavior {
    allowed_methods            = local.media_methods
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = local.content_origin
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = local.caching_optimized
    response_headers_policy_id = one(aws_cloudfront_response_headers_policy.media_cors[*].id)
  }

  ordered_cache_behavior {
    allowed_methods            = local.media_methods
    cached_methods             = ["GET", "HEAD"]
    path_pattern               = "/workouts/*"
    target_origin_id           = local.content_origin
    viewer_protocol_policy     = "https-only"
    cache_policy_id            = aws_cloudfront_cache_policy.media.id
    response_headers_policy_id = one(aws_cloudfront_response_headers_policy.media_cors[*].id)
  }

  ordered_cache_behavior {
    allowed_methods            = local.media_methods
    cached_methods             = ["GET", "HEAD"]
    path_pattern               = "/favicon.ico"
    target_origin_id           = local.content_origin
    viewer_protocol_policy     = "https-only"
    cache_policy_id            = local.caching_optimized
    response_headers_policy_id = one(aws_cloudfront_response_headers_policy.media_cors[*].id)
  }

  ordered_cache_behavior {
    allowed_methods            = local.media_methods
    cached_methods             = ["GET", "HEAD"]
    path_pattern               = "/avatars/*"
    target_origin_id           = local.content_origin
    viewer_protocol_policy     = "https-only"
    cache_policy_id            = aws_cloudfront_cache_policy.media.id
    response_headers_policy_id = one(aws_cloudfront_response_headers_policy.media_cors[*].id)
  }

  # Static, unauthenticated CDN objects (static/templates, static/exercises/*):
  # the only behavior on this distribution that compresses, since the exercise
  # library files are ~650 KB of instruction markdown each.
  ordered_cache_behavior {
    allowed_methods            = local.media_methods
    cached_methods             = ["GET", "HEAD"]
    path_pattern               = "/static/*"
    target_origin_id           = local.content_origin
    viewer_protocol_policy     = "https-only"
    compress                   = true
    cache_policy_id            = local.caching_optimized
    response_headers_policy_id = one(aws_cloudfront_response_headers_policy.media_cors[*].id)
  }

  viewer_certificate {
    ssl_support_method  = "sni-only"
    acm_certificate_arn = var.media_distribution_ssl_certificate
  }

  aliases = var.media_distribution_aliases

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

resource "aws_cloudfront_distribution" "web" {
  enabled = true
  comment = "Heart of yours, website and app"

  origin {
    origin_access_control_id = aws_cloudfront_origin_access_control.heart.id
    domain_name              = var.static_bucket.bucket_regional_domain_name
    origin_id                = local.static_origin
    origin_path              = "/site"
  }

  origin {
    domain_name              = var.content_bucket.bucket_regional_domain_name
    origin_id                = local.content_origin
    origin_access_control_id = aws_cloudfront_origin_access_control.heart.id
    origin_path              = "/static"
  }

  origin {
    domain_name = var.firebase_auth_domain
    origin_id   = local.firebase_origin

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.static_origin
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = local.caching_optimized
  }

  ordered_cache_behavior {
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    path_pattern             = "/__/auth/*"
    target_origin_id         = local.firebase_origin
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
    origin_request_policy_id = local.all_viewer_except_host_header
    cache_policy_id          = local.caching_disabled
  }

  ordered_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    path_pattern           = "templates"
    target_origin_id       = local.content_origin
    viewer_protocol_policy = "https-only"
    cache_policy_id        = local.caching_optimized
  }

  # Paths under the apex are client-side routes, not objects: nothing is keyed
  # `/profile/settings/account`, and behind an OAC without ListBucket S3 answers
  # a missing key 403 AccessDenied in XML — which is what a deep link opened
  # without the app installed used to land on. 404 is mapped alongside it
  # because which of the two S3 returns depends on the bucket policy.
  #
  # Distribution-wide, the only form CloudFront offers, so it reaches
  # `/__/auth/*` and `templates` too: an error from either now surfaces as the
  # site index with a 200. That is affordable here and would not have been
  # while the API shared this distribution, where it would have turned
  # `route_not_found` and the `anonymous_account` 403 into an HTML page.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  viewer_certificate {
    ssl_support_method  = "sni-only"
    acm_certificate_arn = var.web_distribution_ssl_certificate
  }

  aliases = var.web_distribution_aliases

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

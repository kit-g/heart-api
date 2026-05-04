resource "aws_cloudfront_origin_access_control" "heart" {
  name                              = "heart-oac"
  description                       = "OAC for the Heart app resources"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "content_cloudfront_access" {
  bucket = aws_s3_bucket.content.id

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
        Resource = "${aws_s3_bucket.content.arn}/*"
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
  bucket = aws_s3_bucket.static.id

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
        Resource = "${aws_s3_bucket.static.arn}/*"
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
    domain_name              = aws_s3_bucket.content.bucket_regional_domain_name
    origin_id                = local.content_origin
    origin_access_control_id = aws_cloudfront_origin_access_control.heart.id
    # empty, as per
    # https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-cloudfront-distribution-s3originconfig.html#cfn-cloudfront-distribution-s3originconfig-originaccessidentity
    origin_path = ""
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.content_origin
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = local.caching_optimized
  }

  ordered_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    path_pattern           = "/workouts/*"
    target_origin_id       = local.content_origin
    viewer_protocol_policy = "https-only"
    cache_policy_id        = aws_cloudfront_cache_policy.media.id
  }

  ordered_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    path_pattern           = "/favicon.ico"
    target_origin_id       = local.content_origin
    viewer_protocol_policy = "https-only"
    cache_policy_id        = local.caching_optimized
  }

  ordered_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    path_pattern           = "/avatars/*"
    target_origin_id       = local.content_origin
    viewer_protocol_policy = "https-only"
    cache_policy_id        = aws_cloudfront_cache_policy.media.id
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
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id                = local.static_origin
    origin_path              = "/site"
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

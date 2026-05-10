output "media_distribution" {
  value = {
    id             = aws_cloudfront_distribution.media.id
    domain_name    = aws_cloudfront_distribution.media.domain_name
    hosted_zone_id = aws_cloudfront_distribution.media.hosted_zone_id
  }
}

output "web_distribution" {
  value = {
    id             = aws_cloudfront_distribution.web.id
    domain_name    = aws_cloudfront_distribution.web.domain_name
    hosted_zone_id = aws_cloudfront_distribution.web.hosted_zone_id
  }
}
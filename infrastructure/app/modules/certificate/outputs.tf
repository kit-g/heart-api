output "arn" {
  description = "The certificate's ARN, handed on only once it is issued: whatever takes it waits for validation."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

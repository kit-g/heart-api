# Apex zone — single hosted zone for heart-of.me, lives in this dev account today
# and will keep doing so even after a prod account exists (apex doesn't move).

resource "aws_route53_zone" "apex" {
  name    = var.apex_domain
  comment = "${var.apex_domain} hosted zone"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "apex_mx" {
  zone_id = aws_route53_zone.apex.id
  name    = var.apex_domain
  type    = "MX"
  ttl     = 14400
  records = [
    "10 mx1.improvmx.com",
    "20 mx2.improvmx.com",
  ]
}

resource "aws_route53_record" "apex_txt" {
  zone_id = aws_route53_zone.apex.id
  name    = var.apex_domain
  type    = "TXT"
  ttl     = 14400
  records = [
    "v=spf1 include:spf.improvmx.com ~all",
    "v=spf1 include:_spf.firebasemail.com ~all",
    "google-site-verification=r5-Cw1hkYWb3xDhuBaLOv_dNujEY3h-w512B0KtSUSk",
    "firebase=${var.firebase_prod_project_id}"
  ]
}

resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.apex.id
  name    = "_dmarc.${var.apex_domain}"
  type    = "TXT"
  ttl     = 3600
  records = ["v=DMARC1; p=none; rua=mailto:${var.communications_email}"]
}

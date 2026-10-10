# The old apex zone, retired: prod's zone has been authoritative for heart-of.me
# since 2026-10-08, and the 48 hours the old delegation could stay cached have
# passed. This root exists only to be destroyed (README, phase 7).

resource "aws_route53_zone" "apex" {
  name    = var.apex_domain
  comment = "${var.apex_domain} hosted zone"
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

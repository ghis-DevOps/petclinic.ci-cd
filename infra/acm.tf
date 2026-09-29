# Regional certificate for the ALB's HTTPS listener.
resource "aws_acm_certificate" "alb" {
  count             = local.use_custom_domain ? 1 : 0
  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront always requires its certificate in us-east-1.
resource "aws_acm_certificate" "cloudfront" {
  count             = local.use_custom_domain ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Both certificates validate the same domain and use the same DNS validation
# record. Keep the for_each key static; ACM's record name is unknown until apply.
locals {
  cert_validation_records = local.use_custom_domain ? { domain = true } : {}
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.cert_validation_records

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = tolist(aws_acm_certificate.alb[0].domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.alb[0].domain_validation_options)[0].resource_record_type
  records = [tolist(aws_acm_certificate.alb[0].domain_validation_options)[0].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "alb" {
  count                   = local.use_custom_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.alb[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_acm_certificate_validation" "cloudfront" {
  count                   = local.use_custom_domain ? 1 : 0
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

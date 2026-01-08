# modules/route53/outputs.tf

# [필수 1] 루트 main.tf에서 최종 도메인 연결(A레코드) 할 때 필요함
output "zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = data.aws_route53_zone.main.zone_id
}

# [필수 2] Ingress가 HTTPS 적용할 때 필요함
output "acm_certificate_arn" {
  description = "Certificate ARN for Ingress"
  value       = aws_acm_certificate.cert.arn
}
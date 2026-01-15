# [필수 1] 루트 main.tf에서 최종 도메인 연결(A레코드) 할 때 필요함
output "zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = aws_route53_zone.main.zone_id
}

# [필수 2] 도메인 등록처 네임서버 업데이트를 위해 필요함
output "name_servers" {
  description = "Route53 Name Servers"
  value       = aws_route53_zone.main.name_servers
}

# [필수 3] Ingress가 HTTPS 적용할 때 필요함 (검증 완료된 ARN 반환)
output "acm_certificate_arn" {
  description = "Certificate ARN for Ingress (Validated)"
  # cert.arn 대신 validation 리소스의 arn을 사용하면, 인증서가 '발급 완료'된 후 값을 넘겨줍니다.
  value       = aws_acm_certificate_validation.cert.certificate_arn
}
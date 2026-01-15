variable "domain_name" {
  type = string
}

variable "project_name" {
  type = string
}

# 1. [수정] data -> resource로 변경
# 이유: destroy하면 Zone도 사라져야 하므로, Terraform이 직접 생성/삭제를 관리해야 합니다.
resource "aws_route53_zone" "main" {
  name = var.domain_name
}
/*
# 2. [추가] 도메인 등록처(AWS Domains)의 네임서버를 자동으로 업데이트!
# 설명: Zone이 새로 만들어질 때마다 생기는 새로운 NS 4개를 실제 도메인 설정에 덮어씌웁니다.
resource "aws_route53domains_registered_domain" "main" {
  domain_name = var.domain_name

  dynamic "name_server" {
    for_each = aws_route53_zone.main.name_servers
    content {
      name = name_server.value
    }
  }

  # Zone이 먼저 만들어져야 함
  depends_on = [aws_route53_zone.main]
}*/

# 3. [추가] 전파 대기 시간 (Time Sleep)
# 설명: 네임서버를 바꿔도 전 세계에 퍼지는 데 시간이 걸립니다.
#       바로 인증서 발급을 시도하면 실패하므로 60초 강제 휴식을 줍니다.
resource "time_sleep" "wait_for_dns_propagation" {
  create_duration = "60s" # 1분 대기 (만약 타임아웃 나면 120s로 늘리세요)

  # 네임서버 업데이트가 끝난 뒤에 카운트다운
  #depends_on = [aws_route53domains_registered_domain.main]
  depends_on = [aws_route53_zone.main]
}

# 4. ACM 인증서 생성
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.domain_name}"
  ]

  tags = {
    Name = "${var.project_name}-acm"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 5. 인증서 검증용 DNS 레코드 생성
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  
  # [수정] resource의 zone_id를 참조 (data 아님)
  zone_id         = aws_route53_zone.main.zone_id
}

# 6. 인증서 검증 완료 대기
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  # [핵심] 60초 대기가 끝난 뒤에 검증을 시작해라!
  depends_on = [time_sleep.wait_for_dns_propagation]
}

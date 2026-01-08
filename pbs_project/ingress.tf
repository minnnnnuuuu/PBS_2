resource "kubernetes_ingress_v1" "web_ingress" {
  metadata {
    name      = "pbs-web-ingress"
    namespace = "default" # 웹서버가 떠 있는 네임스페이스
    annotations = {
      # [핵심] AWS 로드밸런서(ALB)를 만들어라
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      # [추가 1] HTTP로 들어오면 HTTPS로 리다이렉트
      "alb.ingress.kubernetes.io/listen-ports" = jsonencode([
        {"HTTP": 80},
        {"HTTPS": 443}
      ])
      # [추가 2] main.tf에서 만든 인증서 붙이기 (이게 없으면 HTTPS 불가)
      # 주의: main.tf의 인증서 리소스 이름을 참조해야 합니다.
      #"alb.ingress.kubernetes.io/certificate-arn" = aws_acm_certificate.cert.arn
      "alb.ingress.kubernetes.io/certificate-arn" = module.route53_acm.acm_certificate_arn
    }
  }

  spec {
    rule {
      # [여기] 우리가 산 도메인 입력!
      host = "soldesk-group4-pbs-project.click"
      
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "pbs-web-service" # 연결할 웹 서비스 이름
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
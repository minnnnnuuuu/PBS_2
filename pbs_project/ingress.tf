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
      host = "soldesk-group4-pbs-project.click"
      
      http {
        # 1. 메인 접속 (프론트엔드) -> "/"
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "pbs-web-service"
              port {
                number = 80
              }
            }
          }
        }

        # 2. 백엔드 접속 (API) -> "/api"
        # (주의: 여기 문법을 YAML(:)이 아니라 HCL(=)로 써야 에러가 안 납니다!)
        path {
          path = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = "pbs-app-service"
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

# 1. ArgoCD용 Ingress (네임스페이스가 'argocd'인 점 주의!)
resource "kubernetes_ingress_v1" "argocd_ingress" {
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"  # ★중요: ArgoCD는 보통 이 방에 설치됩니다.
    annotations = {
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      
      # ArgoCD는 자체적으로 HTTPS를 써서, 백엔드 프로토콜을 HTTPS로 맞춰야 할 수도 있음
      "alb.ingress.kubernetes.io/backend-protocol" = "HTTPS"
      
      # 인증서 (모듈에서 가져온 것 공용 사용)
      "alb.ingress.kubernetes.io/certificate-arn" = module.route53_acm.acm_certificate_arn
      
      # HTTP -> HTTPS 리다이렉트
      "alb.ingress.kubernetes.io/listen-ports" = jsonencode([{"HTTP": 80}, {"HTTPS": 443}])
    }
  }

  spec {
    rule {
      host = "argocd.soldesk-group4-pbs-project.click" # 서브도메인
      
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server" # 실제 ArgoCD 서비스 이름
              port {
                number = 443 # ArgoCD 서비스 포트
              }
            }
          }
        }
      }
    }
  }
}
# 1. 메인 웹 서비스용 Ingress
resource "kubernetes_ingress_v1" "web_ingress" {
  metadata {
    name      = "pbs-web-ingress"
    namespace = "default"
    annotations = {
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      
      # HTTP -> HTTPS 리다이렉트
      "alb.ingress.kubernetes.io/listen-ports" = jsonencode([{"HTTP": 80}, {"HTTPS": 443}])
      
      # 인증서 연결
      "alb.ingress.kubernetes.io/certificate-arn" = module.route53_acm.acm_certificate_arn

      # 상태 검사 설정
      "alb.ingress.kubernetes.io/success-codes"   = "200,404,301"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/"
    }
  }

  # [핵심] ALB 주소가 생성될 때까지 테라폼이 기다리도록 설정 (에러 방지)
  wait_for_load_balancer = true 

  spec {
    rule {
      host = "soldesk-group4-pbs-project.click"
      
      http {
        # [수정됨] 백엔드 API 접속 ("/api"로 시작하는 모든 요청) - 채팅/업로드용
        path {
          path = "/api"      
          path_type = "Prefix"
          backend {
            service {
              name = "hybrid-ai-service" 
              port {
                number = 80
              }
            }
          }
        }

        # 메인 웹사이트 접속
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
      }
    }
  }


  # [추가 2] 컨트롤러가 설치된 후에 Ingress를 만들도록 강제 (module 이름 확인 필요)
  # 만약 Load Balancer Controller가 'module.eks' 안에서 설치된다면 아래처럼 작성
  depends_on = [
    module.eks,
    helm_release.aws_lbc
  ]
}

# 2. ArgoCD용 Ingress
resource "kubernetes_ingress_v1" "argocd_ingress" {
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"
    annotations = {
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      "alb.ingress.kubernetes.io/backend-protocol" = "HTTPS"
      "alb.ingress.kubernetes.io/certificate-arn" = module.route53_acm.acm_certificate_arn
      "alb.ingress.kubernetes.io/listen-ports" = jsonencode([{"HTTP": 80}, {"HTTPS": 443}])
    }
  }

  # [핵심] ALB 주소가 생성될 때까지 기다림
  wait_for_load_balancer = true

  spec {
    rule {
      host = "argocd.soldesk-group4-pbs-project.click"
      
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                number = 443
              }
            }
          }
        }
      }
    }
  }

  # 순서 보장 (네임스페이스 생성 후 Ingress 생성)
  depends_on = [
    helm_release.argocd,
    module.route53_acm,
    helm_release.aws_lbc
  ]
}
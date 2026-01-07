resource "kubernetes_ingress_v1" "web_ingress" {
  metadata {
    name      = "pbs-web-ingress"
    namespace = "default" # 웹서버가 떠 있는 네임스페이스
    annotations = {
      # [핵심] AWS 로드밸런서(ALB)를 만들어라
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
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
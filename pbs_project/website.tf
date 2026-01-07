# 1. 웹사이트 배포 (Deployment) - 실제 서버 띄우기
resource "kubernetes_deployment" "pbs_web" {
  metadata {
    name      = "pbs-web"
    namespace = "default"
    labels = {
      app = "pbs-web"
    }
  }

  spec {
    replicas = 2 # 서버 2대 띄우기 (안정성)

    selector {
      match_labels = {
        app = "pbs-web"
      }
    }

    template {
      metadata {
        labels = {
          app = "pbs-web"
        }
      }

      spec {
        container {
          image = "nginx:alpine" # [수정필요] 나중에 팀원이 준 ECR 주소로 바꾸세요! (예: 123...ecr.../pbs-web:latest)
          name  = "pbs-web"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}

# 2. 서비스 (Service) - 인그레스와 연결하는 통로
resource "kubernetes_service" "pbs_web_svc" {
  metadata {
    name      = "pbs-web-service" # ingress.tf에 적은 이름과 똑같아야 함!
    namespace = "default"
  }

  spec {
    selector = {
      app = "pbs-web"
    }
    
    port {
      port        = 80
      target_port = 80
    }

    type = "NodePort" # ALB 인그레스는 보통 NodePort를 사용
  }
}
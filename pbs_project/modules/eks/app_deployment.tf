# 1. 애플리케이션 Deployment (기차 만들기)
resource "kubernetes_deployment" "pbs_app" {
  metadata {
    name      = "pbs-app-deployment"
    namespace = "default"
    labels = {
      app = "pbs-app"
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "pbs-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "pbs-app"
        }
      }

      spec {
        container {
          image = "nginxdemos/hello" # 접속 시 예쁜 화면을 보여주는 이미지
          name  = "pbs-app"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}

# 2. 애플리케이션 Service (역 만들기)
resource "kubernetes_service" "pbs_app_service" {
  metadata {
    name      = "pbs-app-service" # [중요] VirtualService가 찾는 바로 그 이름!
    namespace = "default"
  }

  spec {
    selector = {
      app = "pbs-app"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP" # 내부 통신용으로 설정 (Istio가 밖에서 연결해줌)
  }
}
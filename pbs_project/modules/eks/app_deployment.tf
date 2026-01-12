# 1. 애플리케이션 Deployment (기차 만들기)
resource "kubernetes_deployment" "pbs_app" {
  metadata {
    name      = "hybrid-ai-deployment"
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
        service_account_name = "hybrid-ai-sa"
        container {
          image = "198011705652.dkr.ecr.ap-northeast-2.amazonaws.com/hybrid-service:ai-latest" # 접속 시 예쁜 화면을 보여주는 이미지
          name  = "pbs-app"
          env {
            name  = "MILVUS_ADDR"
            value = "milvus-service:19530" # Milvus 서비스 이름과 포트
          }
          env {
            name  = "OLLAMA_ADDR"
            value = "http://ollama-deployment:11434" # Ollama 서비스 이름과 포트
          }

          # [추가 추천] 자원 최적화 - t3.large 환경용
          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          image_pull_policy = "Always"

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
    name      = "hybrid-ai-service" # [중요] VirtualService가 찾는 바로 그 이름!
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
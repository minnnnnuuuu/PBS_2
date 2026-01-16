# 1. 애플리케이션 Deployment (기차 만들기)
resource "kubernetes_deployment" "pbs_app" {
  metadata {
    # 실제 클러스터의 파드 이름과 일치하도록 수정
    name      = "pbs-app-deployment"
    namespace = "default"
    labels = {
      app = "pbs-app"
    }
  }
  # [핵심] 앱이 켜질 때까지 기다리지 말고 바로 성공 처리해!
  wait_for_rollout = false

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
          image = "198011705652.dkr.ecr.ap-northeast-2.amazonaws.com/hybrid-service:ai-latest"
          name  = "pbs-app"

          # [필수] 인수인계 문서에서 강조한 ADDR 환경 변수 ⭐
          env {
            name  = "MILVUS_ADDR"
            value = "milvus-standalone.default.svc.cluster.local:19530" # Milvus 서비스 주소
          }
          env {
            name  = "OLLAMA_ADDR"
            value = "http://ollama-deployment:11434" # Ollama 서비스 주소
          }
          env {
            name  = "DATABASE_ADDR"
            value = "pbs-project-cluster.cluster-c7immc08qoyj.ap-northeast-2.rds.amazonaws.com"
          }
          env {
            name  = "AI_SERVER_URL"
            value = "http://api.cloudreaminu.cloud" # [핵심 변경]
          }
          env {
            name  = "EMBEDDING_SERVER_URL"
            value = "http://api.cloudreaminu.cloud" # [핵심 변경]
          }

          # [최적화] t3.large 자원 부족(Insufficient cpu) 해결 ⭐
          resources {
            requests = {
              cpu    = "100m"  # 0.1 vCPU로 낮춰서 다른 파드와 공존 가능하게 함
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
    name      = "hybrid-ai-service"
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

    type = "ClusterIP"
  }
}
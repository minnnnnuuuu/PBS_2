# 1. Istio Gateway 설정
resource "kubernetes_manifest" "pbs_gateway" {
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "Gateway"
    metadata = {
      name      = "pbs-gateway"
      namespace = "istio-system"
    }
    spec = {
    
      selector = {
        "istio" = "ingress" 
        #istio = "ingressgateway"
      }

      
      servers = [
        {
          port = {
            number   = 80
            name     = "http"
            protocol = "HTTP"
          }
          hosts = ["*"]
        }
      ]
    }
    
  }
  # [중요] 메인 파일의 인그레스 게이트웨이 파드가 먼저 떠야 합니다.
  depends_on = [helm_release.istio_ingress]
}

# 2. Istio VirtualService 설정
resource "kubernetes_manifest" "pbs_virtual_service" {
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "VirtualService"
    metadata = {
      name      = "pbs-vs"
      namespace = "default"
    }
    spec = {
      hosts = ["*"]
      gateways = ["istio-system/pbs-gateway"]
      http = [
        {
          route = [
            {
              destination = {
                host = "pbs-app-service"
                port = {
                  number = 80
                }
              }
            }
          ]
        }
      ]
    }
  }
  # [중요] 게이트웨이 설정이 먼저 생성되어야 합니다.
  depends_on = [kubernetes_manifest.pbs_gateway]
}
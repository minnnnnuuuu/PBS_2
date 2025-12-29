# 1. Gateway API 리소스 (LBC가 이걸 보고 ALB를 만듭니다)
resource "kubernetes_manifest" "pbs_gateway" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "Gateway"
    metadata = {
      name      = "pbs-gateway"
      namespace = "kube-system"
      annotations = {
        # 강현님이 만든 LBC가 이 게이트웨이를 관리하도록 연결
        "alb.networking.k8s.io/scheme" = "internet-facing"
      }
    }
    spec = {
      gatewayClassName = "amazon-lbc" # LBC용 게이트웨이 클래스
      listeners = [{
        name     = "http"
        port     = 80
        protocol = "HTTP"
        allowedRoutes = { namespaces = { from = "All" } }
      }]
    }
  }
}

# 2. 강현님 LBC에 옵션이 빠졌을 경우를 대비한 체크 (중요)
# 강현님 helm_release 부분에 'featureGates = "GatewayAPI=true"'가 있는지 꼭 확인하세요!
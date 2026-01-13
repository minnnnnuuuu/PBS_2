# pbs_project/istio_networking.tf
/*
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
  depends_on = [module.eks]
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
                host = "pbs-web-service"
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
*/
# -----------------------------------------------------------
# [최종 수정] Istio Classic 방식 (Gateway + VirtualService)
# 설명: Terraform Provider 에러 회피를 위해 kubectl로 적용
# -----------------------------------------------------------

# 1. 적용할 매니페스트 (Classic Istio YAML) 생성
resource "local_file" "istio_manifest" {
  filename = "${path.module}/istio_resources.yaml"
  content  = <<YAML
# [1] Istio Gateway
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: pbs-gateway
  namespace: istio-system  # 보통 istio-system에 둡니다
spec:
  selector:
    istio: ingress # [중요] 기본 Istio 인그레스 컨트롤러를 바라봄
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
# [2] VirtualService
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: pbs-vs
  namespace: default
spec:
  hosts:
  - "*"
  gateways:
  - istio-system/pbs-gateway
  http:
  # 1. /api로 시작하는 요청은 백엔드(데이터)로 보낸다
  - match:
    - uri:
        prefix: /api
    rewrite:
      uri: /
    route:
    - destination:
        host: hybrid-ai-service
        port:
          number: 80
  # 2. 나머지 모든(/) 요청은 웹사이트(화면)로 보낸다
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: pbs-web-service
        port:
          number: 80
YAML
}

# 2. EKS 생성 후 kubectl로 적용
resource "null_resource" "apply_istio_resources" {
  triggers = {
    manifest_hash = local_file.istio_manifest.content
    cluster_name  = module.eks.cluster_name
  }

  provisioner "local-exec" {
    # 윈도우 PowerShell용 명령
    command = <<EOT
      aws eks update-kubeconfig --region ap-northeast-2 --name ${module.eks.cluster_name}
      kubectl apply -f ${local_file.istio_manifest.filename}
    EOT
    
    interpreter = ["PowerShell", "-Command"]
  }

  # [중요] EKS가 다 만들어진 뒤에 실행
  depends_on = [module.eks]
}
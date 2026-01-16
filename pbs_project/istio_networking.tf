# pbs_project/istio_networking.tf

# 1. 적용할 매니페스트 (Classic Istio YAML) 생성
resource "local_file" "istio_manifest" {
  filename = "${path.module}/istio_resources.yaml"
  content  = <<YAML
# [1] Istio Gateway
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: pbs-gateway
  namespace: istio-system 
spec:
  selector:
    istio: ingress 
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
# [2] ServiceEntry (온프레미스 AI 도메인 등록)
# [수정] 위 Gateway와 구분하기 위해 --- 를 추가했네.
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: on-premise-ai-api
  namespace: default
spec:
  # Cloudflare에서 설정한 도메인과 정확히 일치함
  hosts:
  - api.cloudreaminu.cloud
  location: MESH_EXTERNAL
  ports:
  - number: 80
    name: http
    protocol: HTTP
  - number: 443
    name: https
    protocol: HTTPS
  resolution: DNS
---
# [3] VirtualService
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
  # 1. /api 요청을 온프레미스 AI(Cloudflare Tunnel)로 라우팅
  - match:
    - uri:
        prefix: /api
    rewrite:
      uri: /
    route:
    - destination:
        host: api.cloudreaminu.cloud 
        port:
          number: 80
    timeout: 180s # Solar 모델의 분석 시간을 고려한 넉넉한 설정

  # 2. 나머지 모든(/) 요청은 웹사이트로 보냄
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: pbs-web-service
        port:
          number: 80
    timeout: 180s
YAML
}

# 2. EKS 생성 후 kubectl로 적용
resource "null_resource" "apply_istio_resources" {
  triggers = {
    manifest_hash = local_file.istio_manifest.content
    cluster_name  = module.eks.cluster_name
  }

  provisioner "local-exec" {
    command = <<EOT
      aws eks update-kubeconfig --region ap-northeast-2 --name ${module.eks.cluster_name}
      
      # 1. 네임스페이스에 Istio 주입 라벨 설정
      kubectl label namespace default istio-injection=enabled --overwrite

      # 2. 통합 매니페스트 적용 (Gateway, ServiceEntry, VirtualService)
      kubectl apply -f ${local_file.istio_manifest.filename}

      # 3. 앱 재시작 (새로운 Istio 설정 반영)
      kubectl rollout restart deployment pbs-app-deployment || true
    EOT
    
    interpreter = ["PowerShell", "-Command"]
  }

  depends_on = [module.eks]
}
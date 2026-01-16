# pbs_project/istio_networking.tf

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
  # 1. /api로 시작하는 요청은 백엔드 앱(pbs-app)으로 보냄
  # (주의: 서비스 이름은 hybrid-ai-service 입니다)
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
    timeout: 180s  # [추가] AI 응답 대기 시간 설정

  # 2. 나머지 모든(/) 요청은 웹사이트(화면)로 보냄
  # (주의: pbs-web-service는 나중에 만드실 예정이므로 지금은 에러 방지를 위해 주석 처리하거나, 
  #  일단 hybrid-ai-service로 몰아주셔도 됩니다. 여기선 그대로 둡니다.)
    
  # 2. 나머지 모든(/) 요청은 웹사이트(화면)로 보낸다
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: pbs-web-service # <--- 이게 없어서 503 에러가 날 수 있지만, 배포는 성공합니다.
        port:
          number: 80
    timeout: 180s  # [추가] AI 응답 대기 시간 설정
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
      
      # 1. 네임스페이스에 Istio 주입 라벨 설정
      kubectl label namespace default istio-injection=enabled --overwrite

      # 2. Istio Gateway & VirtualService 적용
      kubectl apply -f ${local_file.istio_manifest.filename}

      # 3. [수정됨] 실제로 존재하는 배포(Deployment)만 재시작합니다.
      # (없는 것들을 재시작하면 에러가 나서 전체가 멈춥니다!)
      
      # pbs-app-deployment는 확실히 존재하므로 재시작 (O)
      kubectl rollout restart deployment pbs-app-deployment
      
      # hybrid-ai-service는 '서비스'이므로 재시작 불가 (X) -> 삭제됨
      # pbs-web-service는 아직 안 만들었으므로 재시작 불가 (X) -> 삭제됨
    EOT
    
    interpreter = ["PowerShell", "-Command"]
  }

  depends_on = [module.eks]
}
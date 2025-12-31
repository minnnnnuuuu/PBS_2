# 1. 게이트웨이 설정을 담은 임시 YAML 파일 자동 생성
resource "local_file" "gateway_manifest" {
  filename = "${path.module}/pbs-gateway.yaml"
  content  = <<EOT
#----------- 추가된 부분 -----------
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: amazon-lbc
spec:
  controllerName: managed.aws.amazon.com/gateway-controller
---
#----------------------------------
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: pbs-gateway
  namespace: kube-system
  annotations:
    alb.networking.k8s.io/scheme: internet-facing
    alb.networking.k8s.io/wafv2-acl-arn: ${var.waf_acl_arn}
spec:
  gatewayClassName: amazon-lbc
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
EOT
}

# 2. 접속 정보 갱신 + CRD 설치 + 게이트웨이 배포 (100% 자동화)
resource "null_resource" "install_gateway_all" {
  triggers = {
    # 클러스터 엔드포인트가 바뀌면 재실행
    cluster_endpoint = aws_eks_cluster.this.endpoint
    manifest_hash    = sha256(local_file.gateway_manifest.content)
  }

  provisioner "local-exec" { 
    #----------- 이 부분 수정 -----------
    # 이유: 윈도우 CMD 대신 파워쉘을 명시적으로 사용하고, 
    # 명령어 사이의 공백 에러를 방지하기 위해 세미콜론(;)으로 연결했습니다.
    interpreter = ["PowerShell", "-Command"]
    command     = <<EOT
      aws eks update-kubeconfig --region ap-northeast-2 --name ${aws_eks_cluster.this.name} ;
      kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml ;
      kubectl apply -f ${abspath(local_file.gateway_manifest.filename)}
    EOT
    #----------------------------------
    # 윈도우(PowerShell/CMD)에서도 안전하게 돌아가는 명령어 구조입니다.
    #command = <<EOT
    #  aws eks update-kubeconfig --region ap-northeast-2 --name ${aws_eks_cluster.this.name} && ^
    #  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml && ^
    #  kubectl apply -f ${local_file.gateway_manifest.filename}
    #EOT
  }

  depends_on = [local_file.gateway_manifest]
}
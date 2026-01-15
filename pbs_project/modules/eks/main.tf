# pbs_project/modules/eks/main.tf

# -----------------------------------------------------------
# 1. Variables (입력 변수)
# -----------------------------------------------------------
#variable "project_name" { type = string }
#variable "environment"  { type = string }
#variable "vpc_id"        { type = string }
#variable "subnet_ids"    { type = list(string) }
#variable "node_role_arn" { type = string } # IAM 모듈에서 전달받음
#variable "waf_acl_arn"   { type = string }

# -----------------------------------------------------------
# 2. IAM Roles (클러스터 권한)
# -----------------------------------------------------------
resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# -----------------------------------------------------------
# 3. EKS Cluster (v1.31)
# -----------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = "${var.project_name}-${var.environment}-cluster"
  role_arn = aws_iam_role.cluster.arn
  version  = "1.31"

  vpc_config {
    subnet_ids = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

resource "aws_eks_addon" "efs_csi_driver" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "aws-efs-csi-driver"
  addon_version = "v2.0.7-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# -----------------------------------------------------------
# 4. Managed Node Group (워커 노드)
# -----------------------------------------------------------
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project_name}-${var.environment}-node-group"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }
  tags = {
    Name = "${var.project_name}-eks-worker-${var.environment}" # 여기에 이름을 넣으세요!
  }

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.large"]
  capacity_type  = "ON_DEMAND"

  depends_on = [aws_eks_cluster.this]
}

# -----------------------------------------------------------
# 5. OIDC & Istio/Gateway API 자동화
# -----------------------------------------------------------
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# Gateway API CRD 설치 및 Kubeconfig 갱신
#resource "null_resource" "gateway_api_crds" {
#  provisioner "local-exec" {
#    command = <<EOT
#      aws eks update-kubeconfig --region ap-northeast-2 --name ${aws_eks_cluster.this.name}
#      kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
#    EOT
#  }
#  depends_on = [aws_eks_cluster.this]
#}

resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
  depends_on = [aws_eks_node_group.this] # 노드가 뜬 후에 설치하도록 변경
  #depends_on       = [null_resource.gateway_api_crds]
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = "istio-system"
  depends_on = [helm_release.istio_base]
}
/*
resource "kubernetes_manifest" "pbs_gateway" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "Gateway"
    "metadata" = {
      "name"      = "pbs-gateway"
      "namespace" = "default"
    }
    "spec" = {
      "gatewayClassName" = "istio"
      "listeners" = [{
        "name"     = "http"
        "port"     = 80
        "protocol" = "HTTP"
        "allowedRoutes" = { "namespaces" = { "from" = "All" } }
      }]
    }
  }
  depends_on = [helm_release.istiod]
}

resource "kubernetes_manifest" "pbs_http_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "pbs-http-route"
      "namespace" = "default"
    }
    "spec" = {
      "parentRefs" = [{ "name" = "pbs-gateway" }]
      "rules" = [{
        "matches" = [{ "path" = { "type" = "PathPrefix", "value" = "/" } }]
        "backendRefs" = [{ "name" = "pbs-test-svc", "port" = 80 }]
      }]
    }
  }
  depends_on = [kubernetes_manifest.pbs_gateway]
}
*/
# -----------------------------------------------------------
# 6. 보안 그룹 규칙 (수동 설정을 자동화)
# -----------------------------------------------------------
/*
resource "aws_security_group_rule" "cluster_self_allow" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  self              = true
  description       = "Allow nodes to communicate with each other (Self)"
}*/

resource "aws_security_group_rule" "allow_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# 실제 외부 트래픽을 받는 '자동차(Controller)' 설치
resource "helm_release" "istio_ingress" {
  name       = "istio-ingress"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = "istio-system"

  set {
    name  = "autoscaling.enabled"
    value = "true" # [추가] 자동 확장 활성화
  }

  set {
    name  = "autoscaling.minReplicas"
    value = "2" # [추가] 최소 2개의 일꾼 유지 (AZ A, C에 하나씩)
  }

  # [추가] 가용 영역(AZ)별로 일꾼을 강제로 찢어서 배치하는 설정
  set {
    name  = "topologySpreadConstraints[0].maxSkew"
    value = "1" # [추가]
  }
  set {
    name  = "topologySpreadConstraints[0].topologyKey"
    value = "topology.kubernetes.io/zone" # [추가] 영역(Zone)을 기준으로 분산
  }
  set {
    name  = "topologySpreadConstraints[0].whenUnsatisfiable"
    value = "DoNotSchedule" # [추가] 한쪽에 몰릴 바에는 띄우지 말고 대기 (강력한 분산)
  }
  set {
    name  = "topologySpreadConstraints[0].labelSelector.matchLabels.istio"
    value = "ingress" # [추가]
  }
  

  #=========추가0105
  # 1. HTTP (80) 포트 설정
  set {
    name  = "service.ports[1].name"
    value = "http2"
  }
  set {
    name  = "service.ports[1].port"
    value = "80"
  }
  set {
    name  = "service.ports[1].nodePort"
    value = "31620"
  }

  # 2. Health Check (15021) 포트 설정
  set {
    name  = "service.ports[0].name"
    value = "status-port"
  }
  set {
    name  = "service.ports[0].port"
    value = "15021"
  }
  set {
    name  = "service.ports[0].nodePort"
    value = "32060"
  }

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  depends_on = [aws_eks_node_group.this, helm_release.istiod]
}

# -----------------------------------------------------------
# [추가] AWS Load Balancer Controller (LBC)를 위한 IAM 역할 (IRSA)
# -----------------------------------------------------------
/*
# 1. LBC가 사용할 IAM 정책 (AWS 공식 문서 기반)
resource "aws_iam_policy" "lbc_policy" {
  name        = "${var.project_name}-${var.environment}-AWSLoadBalancerControllerIAMPolicy"
  description = "AWS Load Balancer Controller Policy"
  
  # 실제 운영 환경에서는 AWS 공식 JSON을 다운로드 받아 사용하는 것이 좋지만,
  # 지금은 필수 권한만 간단히 포함하거나, 이미 받아둔 json 파일이 있다면 file()로 읽어야 합니다.
  # 일단 에러를 넘기기 위해 정책 내용은 비워두거나 기본값으로 둡니다.
  # (나중에 실제 로드밸런서 생성 시 권한 에러가 나면 이 부분을 보강해야 합니다.)
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["ec2:Describe*"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
*/
# [추가] 1. AWS 공식 정책 파일 다운로드 (이 부분이 새로 들어가야 함!)
data "http" "lbc_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json"
}

# [수정] 2. 다운로드한 정책을 적용
resource "aws_iam_policy" "lbc_policy" {
  name        = "${var.project_name}-${var.environment}-AWSLoadBalancerControllerIAMPolicy"
  description = "AWS Load Balancer Controller Policy"

  # [변경] 기존의 jsonencode(...)를 지우고 아래 한 줄로 교체!
  policy = data.http.lbc_iam_policy.response_body
}


# 2. LBC를 위한 IAM 역할 (OIDC 신뢰 관계 설정 포함)
resource "aws_iam_role" "lbc_role" {
  name = "${var.project_name}-${var.environment}-lbc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })
}

# 3. 역할과 정책 연결
resource "aws_iam_role_policy_attachment" "lbc_attach" {
  policy_arn = aws_iam_policy.lbc_policy.arn
  role       = aws_iam_role.lbc_role.name
}

# -----------------------------------------------------------
# [추가] AWS EBS CSI Driver (블록 스토리지용)
# -----------------------------------------------------------

# 1. EBS Driver가 사용할 IAM 역할 (IRSA)
# (이게 있어야 쿠버네티스가 AWS에 "디스크 만들어줘"라고 명령할 수 있습니다)
resource "aws_iam_role" "ebs_csi_driver" {
  name = "${var.project_name}-${var.environment}-ebs-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

# 2. 역할에 AWS 관리형 정책(AmazonEBSCSIDriverPolicy) 연결
resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver.name
}

# 3. EKS Add-on으로 드라이버 설치
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.35.0-eksbuild.1" # 최신 버전 중 하나 (v1.31 클러스터 호환)
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn # 위에서 만든 권한 연결

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  depends_on = [aws_eks_node_group.this] # 노드가 생긴 뒤에 설치하는 게 안전합니다.
}
# [추가] PVC가 사용할 스토리지 클래스 정의
resource "kubernetes_storage_class" "ebs_sc" {
  metadata {
    name = "ebs-sc"
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  reclaim_policy      = "Delete"
  parameters = {
    type = "gp3" 
  }
  # 드라이버가 설치된 후에 만들어야 함
  depends_on = [aws_eks_addon.ebs_csi_driver]
}


# ==========================================================================
# 1. Milvus 전용 저장소 (PVC)
resource "kubernetes_persistent_volume_claim" "milvus_pvc" {
  metadata {
    name      = "milvus-pvc"
    namespace = "default"
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    storage_class_name = "ebs-sc"

    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
  timeouts {
    create = "20m" # 20분으로 늘림
  }
}

resource "kubernetes_deployment" "milvus_standalone" {
  metadata {
    name      = "milvus-standalone"
    namespace = "default"
    labels    = { app = "milvus-standalone" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "milvus-standalone" } }

    template {
      metadata { labels = { app = "milvus-standalone" } }
      spec {
        service_account_name = "hybrid-ai-sa"

        container {
          name    = "milvus"
          image   = "milvusdb/milvus:v2.3.15"
          command = ["milvus", "run", "standalone"]

          env {
            name  = "ETCD_ENDPOINTS"
            value = "etcd.default.svc.cluster.local:2379"
          }
          env {
            name  = "COMMON_STORAGE_TYPE"
            value = "minio"
          }
          env {
            name  = "MINIO_ADDRESS"
            value = "s3.ap-northeast-2.amazonaws.com"
          }
          env {
            name  = "MINIO_PORT"
            value = "443" # ⭐ 9000번 포트 타임아웃 방지
          }
          env {
            name  = "MINIO_BUCKET_NAME"
            value = "pbs-project-ai-data-dev-v1"
          }
          env {
            name  = "MINIO_USE_SSL"
            value = "true"
          }
          env {
            name  = "MINIO_USE_IAM"
            value = "true"
          }
          env {
            name  = "MINIO_CLOUD_PROVIDER"
            value = "aws"
          }

          resources {
            requests = { cpu = "500m", memory = "1Gi" }
            limits   = { cpu = "1000m", memory = "2Gi" }
          }

          volume_mount {
            name       = "milvus-storage"
            mount_path = "/var/lib/milvus"
          }
        }
        volume {
          name = "milvus-storage"
          persistent_volume_claim { claim_name = "milvus-pvc" }
        }
      }
    }
  }
  timeouts {
    create = "20m" # 20분으로 늘림
  }
}

# 3. Milvus Service
resource "kubernetes_service" "milvus_standalone" {
  metadata {
    name      = "milvus-standalone"
    namespace = "default"
  }

  spec {
    selector = {
      app = "milvus-standalone"
    }

    port {
      name        = "milvus-port"
      port        = 19530
      target_port = 19530
    }

    port {
      name        = "metrics-port"
      port        = 9091
      target_port = 9091
    }

    type = "ClusterIP"
  }
}
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

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]
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
}*/

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
# modules/eks/main.tf

# -----------------------------------------------------------
# 1. Variables (입력 변수)
# -----------------------------------------------------------
variable "project_name" { type = string }
variable "environment"  { type = string }
variable "vpc_id"       { type = string }
variable "subnet_ids"   { type = list(string) } # Private App Subnets

# -----------------------------------------------------------
# 2. IAM Roles (권한 설정) - ARN 공유 요청 반영
# -----------------------------------------------------------
# (1) 클러스터 역할
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

# (2) 노드 그룹 역할
resource "aws_iam_role" "node" {
  name = "${var.project_name}-${var.environment}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ])
  policy_arn = each.value
  role       = aws_iam_role.node.name
}

# -----------------------------------------------------------
# 3. EKS Cluster (컨트롤 플레인)
# -----------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = "${var.project_name}-${var.environment}-cluster"
  role_arn = aws_iam_role.cluster.arn
  version  = "1.31" # 요청사항: 1.31 권장

  vpc_config {
    subnet_ids = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# ★ [요구사항 2] EFS CSI Driver 자동 설치 ★
resource "aws_eks_addon" "efs_csi_driver" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "aws-efs-csi-driver"
  addon_version = "v2.0.7-eksbuild.1" # 혹은 최신 버전 자동 선택
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# -----------------------------------------------------------
# 4. Managed Node Group (워커 노드)
# -----------------------------------------------------------
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project_name}-${var.environment}-node-group"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  # ★ [요구사항 1] Scaling Config & OS ★
  scaling_config {
    desired_size = 2
    max_size     = 4 # 요청: Max 4
    min_size     = 1
  }

  # Amazon Linux 2023 적용
  ami_type = "AL2023_x86_64_STANDARD"

  # 인스턴스 타입 (비용상 t3.medium 유지, 필요시 m5.large로 변경)
  instance_types = ["t3.medium"] 
  capacity_type  = "ON_DEMAND"

  depends_on = [
    aws_iam_role_policy_attachment.node_policies,
    aws_eks_cluster.this
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-worker"
  }
}
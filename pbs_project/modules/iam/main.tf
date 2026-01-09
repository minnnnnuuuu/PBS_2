variable "name" {}
# [1] 변수 선언 추가 (파일 맨 위나 아래에 추가)
#variable "oidc_provider_arn" {
#  description = "EKS OIDC Provider ARN passed from root"
#  type        = string
#}
# 1. Bastion Host용 역할 및 프로필
resource "aws_iam_role" "bastion_role" {
  name = "${var.name}-bastion-role"
  force_detach_policies = true

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "${var.name}-bastion-profile"
  role = aws_iam_role.bastion_role.name
}

# 2. EKS 노드 그룹용 Service Linked Role (계정당 1개 체크)
data "aws_iam_roles" "eks_nodegroup_role_check" {
  name_regex = "AWSServiceRoleForAmazonEKSNodegroup"
}

resource "aws_iam_service_linked_role" "eks_nodegroup" {
  count            = length(data.aws_iam_roles.eks_nodegroup_role_check.names) == 0 ? 1 : 0
  aws_service_name = "eks-nodegroup.amazonaws.com"
}

# 3. [중요] EKS 노드 그룹용 역할(Role) 정의 (404 에러 해결사)
resource "aws_iam_role" "eks_node_role" {
  name = "${var.name}-dev-eks-node-role"
  force_detach_policies = true

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# 4. EKS 노드 기본 권한들 연결
resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# 5. Gateway API 전용 정책 및 연결
resource "aws_iam_policy" "lbc_gateway_policy" {
  name        = "${var.name}-lbc-gateway-policy"
  description = "Allow AWS Load Balancer Controller to manage Gateway API resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:CreateRule",
        "elasticloadbalancing:DeleteRule",
        "tag:GetResources",
        "tag:TagResources"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lbc_gateway_attach" {
  role       = aws_iam_role.eks_node_role.name # 이제 여기서 참조하니까 에러 안 나요!
  policy_arn = aws_iam_policy.lbc_gateway_policy.arn
}


variable "name" {}

# 1. 역할(Role) 만들기: "나는 EC2가 사용할 신분증입니다"
resource "aws_iam_role" "bastion_role" {
  name = "${var.name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# 2. 권한 붙이기: "이 신분증이 있으면 SSM으로 접속 가능함"
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 3. 프로필 만들기: EC2에게 쥐여줄 수 있는 형태 (목걸이 케이스)
resource "aws_iam_instance_profile" "bastion_profile" {
  name = "${var.name}-bastion-profile"
  role = aws_iam_role.bastion_role.name
}

# 2. [필수] EKS 노드 그룹용 Service Linked Role (계정당 1개)
# =========================================================

# [추가] "이미 있으면 가져와!" 라고 코드로 명시하는 부분

# [수정] 이미 있는지 먼저 확인합니다.
data "aws_iam_roles" "eks_nodegroup_role_check" {
  name_regex = "AWSServiceRoleForAmazonEKSNodegroup"
}

# [수정] 검색 결과가 없을 때만(count = 0일 때) 생성합니다.
resource "aws_iam_service_linked_role" "eks_nodegroup" {
  count            = length(data.aws_iam_roles.eks_nodegroup_role_check.names) == 0 ? 1 : 0
  aws_service_name = "eks-nodegroup.amazonaws.com"
}

# 이 역할은 계정 전체에 딱 하나만 있어야 하므로, 
# EKS 모듈(여러 번 생성 가능)에 넣지 않고 여기서 관리합니다.
#resource "aws_iam_service_linked_role" "eks_nodegroup" {
#  aws_service_name = "eks-nodegroup.amazonaws.com"
#}

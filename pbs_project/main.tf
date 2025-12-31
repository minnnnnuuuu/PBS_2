# 파일 위치: pbs_project/main.tf

# VPC (네트워크) 모듈 호출
module "vpc" {
  source = "./modules/vpc"

  name     = "${var.project_name}-vpc"
  vpc_cidr = var.vpc_cidr # 아키텍처 그림에 있는 CIDR
}
# SG (보안그룹) 모듈 호출
module "sg" {
  source = "./modules/security_group"

  name = var.project_name
  vpc_id = module.vpc.vpc_id  # vpc_id는 vpc 모듈이 뱉어내는 결과값(output)
}
module "kms" {
  source = "./modules/kms"

  name = var.project_name
}
# Secret  Manager (DB 금고 비밀번호)
module "secrets_manager" {
  source = "./modules/secrets_manager"

  name = var.project_name
  kms_key_id = module.kms.key_id
}
module "rds" {
  source = "./modules/rds"

  name = var.project_name
  vpc_id = module.vpc.vpc_id

  # DB 전용 서브넷에 넣음
  subnets    = module.vpc.database_subnets 
  
  # DB 전용 보안그룹 적용
  sg_id      = module.sg.rds_sg_id         
  
  # 아까 만든 비밀번호 금고 주소 전달
  secret_arn = module.secrets_manager.secret_arn

  # Secrets Manager가 비밀번호 생성을 완전히 끝낼 때까지 RDS 생성을 대기시킴.
  # secrets manager 모듈이 secret(pw 금고)를 만들고 비밀번호를 넣는 중, RDS 모듈이 secret에 pw를 요구하여, 데이터 조회시도
  # But pw가 아직 저장되지 않았거나 secret이 완전히 준비되지 않아서, 리소스를 찾을 수 없는 에러
  depends_on = [module.secrets_manager]
}
# 6. IAM (EC2 권한 관리)
module "iam" {
  source = "./modules/iam"
  name   = var.project_name
}

# 7. Bastion Host (관리용 서버)
module "bastion" {
  source = "./modules/bastion"

  name                 = var.project_name
  vpc_id               = module.vpc.vpc_id
  subnet_id            = module.vpc.public_subnets[0] # 첫 번째 퍼블릭 서브넷에 배치
  iam_instance_profile = module.iam.instance_profile_name
}

# EFS module
module "efs" {
  source = "./modules/efs"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  
  # [중요] 아키텍처상 Private Data Subnet에 배치
  subnet_ids   = module.vpc.database_subnets
  
  # KMS 모듈에서 만든 키 사용
  kms_key_arn  = module.kms.key_arn
  
  # EKS 노드 그룹의 보안 그룹 ID (EKS 모듈 또는 SG 모듈 output 참조)
  # 예: module.eks.node_security_group_id 또는 module.security_group.eks_node_sg_id
  node_security_group_ids = [module.eks.node_security_group_id] # eks의 생성 후 sg id 넘길 수 있음
  
}

variable "bootstrap_mode" {
  description = "초기 설치 시 Helm 제외 모드"
  type        = bool
  default     = false
}

# EKS module
module "eks" {
  source = "./modules/eks"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  
  # 노드는 반드시 Private App Subnet에 배치
  subnet_ids   = module.vpc.private_subnets 

  # IAM 모듈(Role 생성)이 완전히 끝날 때까지 기다렸다가 시작
  depends_on = [module.iam]
}

# [필수 요구사항] EFS CSI Driver 자동 설치
#resource "aws_eks_addon" "efs_csi_driver" {
#  # EKS 모듈에서 cluster_name을 뱉어내야 합니다!
#  cluster_name = module.eks.cluster_name 
#  addon_name   = "aws-efs-csi-driver"
#  addon_version = "v2.0.7-eksbuild.1" # 최신 버전 사용 권장
  
#  resolve_conflicts_on_create = "OVERWRITE"
#  resolve_conflicts_on_update = "OVERWRITE"

#  depends_on = [module.eks] # 클러스터가 다 만들어진 뒤에 설치
#}

# 이미 설치된 드라이버를 내 테라폼으로 가져와!" (Import)
# destroy 후 첫 apply 시 import 지우기
#import {
#  to = aws_eks_addon.efs_csi_driver
  
  # 형식: "클러스터이름:애드온이름"
  # 아까 에러 로그에 뜬 실제 클러스터 이름을 정확히 넣었습니다.
#  id = "pbs-project-dev-cluster:aws-efs-csi-driver"
#}




# =================================================================
# [팀원 일괄 등록] terraform.tfvars 파일의 명단을 읽어와 자동 적용
# =================================================================

# 1. 입장권 발급 (반복문)
resource "aws_eks_access_entry" "team_members" {
  # 변수에 있는 명단(set)을 하나씩 꺼내서 반복
  for_each      = toset(var.team_members)
  
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value # 명단에 있는 ARN 하나씩 대입
  type          = "STANDARD"
}

# 2. 관리자 권한 부여 (반복문)
resource "aws_eks_access_policy_association" "team_members_policy" {
  for_each      = toset(var.team_members)

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  # 입장권이 먼저 만들어져야 권한을 줄 수 있음
  depends_on = [aws_eks_access_entry.team_members]
}


# EKS 클러스터 인증 정보를 가져옴
# =================================================================
# 7. Helm Provider 설정 (EKS와 통신하기 위한 설정)
# =================================================================

#data "aws_eks_cluster" "cluster" {
#  name = module.eks.cluster_name
#}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
  # name = module.eks.cluster_name
}

#========헬름 초안===========
#provider "helm" {
#  kubernetes = {
#    host                   = data.aws_eks_cluster.cluster.endpoint
#    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
#    token                  = data.aws_eks_cluster_auth.cluster.token
#  }
#}

#=============헬름 모듈 변경================
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

#========쿠버 초안===========
#provider "kubernetes" {
#  host                   = data.aws_eks_cluster.cluster.endpoint
#  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
#  token                  = data.aws_eks_cluster_auth.cluster.token
#}
#=============쿠버 모듈 변경================
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

#========1229 pm 0350 추가===========

# =================================================================
# 8. AWS Load Balancer Controller 설치 (Helm Chart)
# =================================================================
# pbs_project/main.tf (기존 주석 지우고 이 코드로 대체)

resource "helm_release" "aws_lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.1"

  # 1. 게이트웨이 기능 활성화 (아까 모듈 안에 있던 설정)
  set {
    name  = "featureGates"
    value = "GatewayAPI=true"
  }

  # 2. 클러스터 이름 (모듈 결과값 참조)
  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.lbc_role_arn
  }

  set {
    name  = "region"
    value = "ap-northeast-2"
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  # EKS 모듈 생성 후 실행
  depends_on = [module.eks]
}
# pbs_project/main.tf 안에 추가

# =================================================================
# 9. WAF (웹 방화벽)
# =================================================================
module "waf" {
  source = "./modules/waf"
  name   = var.project_name
}

# =================================================================
# 10. ECR (도커 이미지 저장소) - 직접 생성 방식
# =================================================================

# 1. 저장소 생성
resource "aws_ecr_repository" "app_repo" {
  name                 = "${var.project_name}-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true  # 안에 이미지가 있어도 삭제 가능하게

  image_scanning_configuration {
    scan_on_push = true
  }
}

# 2. 수명 주기 정책 (오래된 이미지 삭제)
resource "aws_ecr_lifecycle_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection    = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action       = {
          type = "expire"
        }
      }
    ]
  })
}

# 3. 주소 출력 (나중에 젠킨스가 써야 함)
output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = aws_ecr_repository.app_repo.repository_url
}
# =================================================================
# 11. Route53 (도메인 관리)
# =================================================================
resource "aws_route53_zone" "main" {
  name    = "test.cloudreaminu.cloud"  # 사용자님의 도메인
  comment = "Managed by Terraform for PBS Project"
}

# 나중에 써먹기 위해 Zone ID 출력
output "route53_zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = aws_route53_zone.main.zone_id
}

# 도메인 등록기관(가비아, 후이즈 등)에 등록할 네임서버 목록 출력
output "route53_nameservers" {
  description = "Route53 Name Servers (Update this in your domain registrar)"
  value       = aws_route53_zone.main.name_servers
}
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
resource "aws_eks_addon" "efs_csi_driver" {
  # EKS 모듈에서 cluster_name을 뱉어내야 합니다!
  cluster_name = module.eks.cluster_name 
  addon_name   = "aws-efs-csi-driver"
  addon_version = "v2.0.7-eksbuild.1" # 최신 버전 사용 권장
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.eks] # 클러스터가 다 만들어진 뒤에 설치
}

# 이미 설치된 드라이버를 내 테라폼으로 가져와!" (Import)
# destroy 후 첫 apply 시 import 지우기
import {
  to = aws_eks_addon.efs_csi_driver
  
  # 형식: "클러스터이름:애드온이름"
  # 아까 에러 로그에 뜬 실제 클러스터 이름을 정확히 넣었습니다.
  id = "pbs-project-dev-cluster:aws-efs-csi-driver"
}
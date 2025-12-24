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
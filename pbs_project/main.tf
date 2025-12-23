# 파일 위치: pbs_project/main.tf

# 1. VPC (네트워크) 모듈 호출
module "vpc" {
  source = "./modules/vpc"

  name     = "${var.project_name}-vpc"
  vpc_cidr = var.vpc_cidr # 아키텍처 그림에 있는 CIDR
}
module "sg" {
  source = "./modules/security_group"

  name = var.project_name
  vpc_id = module.vpc.vpc_id  # vpc_id는 vpc 모듈이 뱉어내는 결과값(output)
}
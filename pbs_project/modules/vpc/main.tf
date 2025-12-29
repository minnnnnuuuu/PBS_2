# 파일 위치: pbs_project/modules/vpc/main.tf

# 변수로 받을 값들을 미리 정의 (유연성을 위해)
variable "vpc_cidr" {}
variable "name" {}

# AWS 공식 VPC 모듈 사용 (가장 안정적이고 빠름)
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = var.name
  cidr = var.vpc_cidr

  # 서울 리전의 가용 영역 2개 (AZ-A, AZ-C)
  azs = ["ap-northeast-2a", "ap-northeast-2c"]

  # 1. Public Subnet (외부 통신용: ALB, Bastion)
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1" # ALB가 여기를 찾을 수 있게 표시
  }

  # 2. Private App Subnet (내부 앱용: EKS Node)
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1" # 내부 로드밸런서용 표시
    "karpenter.sh/discovery" = var.name     # 나중에 오토스케일링용
  }

  # 3. Private Data Subnet (데이터용: RDS, EFS) - 모듈의 database_subnets 기능 활용
  database_subnets = ["10.0.20.0/24", "10.0.21.0/24"]
  create_database_subnet_group = true

  # NAT Gateway 설정 (Private Subnet이 인터넷 하려면 필수)
  enable_nat_gateway = true
  single_nat_gateway = false  # 비용 절약용 (실무에선 false로 해서 AZ마다 둠)
  
  # DNS 설정 (필수)
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = "dev"
    Project     = "pbs_project"
  }
}
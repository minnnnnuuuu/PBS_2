# 파일 위치: pbs_project/provider.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9" # 최신 버전 강제
    }
  }
  backend "s3" {
    # 1. 아까 AWS 콘솔에서 손으로 만든 '그 버킷 이름'을 적으세요.
    bucket = "pbs-project-tfstate-soldesk-pbs" 
    
    # 2. S3 안에 저장될 파일 이름입니다. (이건 그대로 두셔도 됩니다)
    key    = "terraform.tfstate"
    
    # 3. 버킷이 있는 리전 (서울)
    region = "ap-northeast-2"

    dynamodb_table = "terraform-locks" 
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-northeast-2"  # 서울 리전
  # 자격 증명(Access Key)은 PC에 aws cli로 로그인되어 있다고 가정합니다.
  # 만약 안 되어 있다면 profile = "default" 등을 추가해야 합니다.
}
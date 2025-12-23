# 파일 위치: pbs_project/provider.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"  # 서울 리전
  # 자격 증명(Access Key)은 PC에 aws cli로 로그인되어 있다고 가정합니다.
  # 만약 안 되어 있다면 profile = "default" 등을 추가해야 합니다.
}
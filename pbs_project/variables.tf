# 파일 위치: pbs_project/variables.tf
# 테라폼에게 우리 프로젝트가 사용할 변수들을 신고하는 과정

variable "project_name" {
  description = "프로젝트 이름 (리소스 접두사로 사용)"
  type        = string
}

variable "region" {
  description = "AWS 리전"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
}
variable "environment" {
  description = "배포 환경 (예: dev, prod)"
  type        = string
}
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

# [추가] 팀원 권한 관리용 변수
variable "team_members" {
  description = "EKS 관리자 권한을 부여할 IAM User ARN 목록"
  type        = list(string)
  default     = []
}
variable "github_token" {
  description = "GitHub Personal Access Token"
  type        = string
  sensitive   = true  # 중요: 로그에 안 찍히게 설정
}
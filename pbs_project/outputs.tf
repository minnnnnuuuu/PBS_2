# pbs_project/outputs.tf
# ==========================================
# 1. 🌐 네트워크 (VPC) - 5개 전부 출력!
# ==========================================
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "Public Subnet 목록"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "Private App Subnet 목록 (EKS용)"
  value       = module.vpc.private_subnets
}

output "database_subnets" {
  description = "Database Subnet 목록 (RDS용)"
  value       = module.vpc.database_subnets
}

output "database_subnet_group" {
  description = "RDS 서브넷 그룹 이름"
  value       = module.vpc.database_subnet_group
}

# ==========================================
# 2. 🛡️ 보안 그룹 (Security Group)
# ==========================================
# ★ 중요: main.tf에 module "security_group" 이라고 적혀있어야 작동합니다.
output "bastion_sg_id" {
  description = "베스천 보안 그룹 ID"
  value       = module.sg.bastion_sg_id
}

output "rds_sg_id" {
  description = "RDS 보안 그룹 ID"
  value       = module.sg.rds_sg_id
}

# ==========================================
# 3. 🔐 시크릿 & 권한 (Secrets & IAM)
# ==========================================
output "secret_arn" {
  description = "비밀번호 금고 ARN"
  value       = module.secrets_manager.secret_arn
}

output "iam_instance_profile" {
  description = "EC2용 IAM 프로필 이름"
  value       = module.iam.instance_profile_name
}

# ==========================================
# 4. 🗄️ 데이터베이스 (RDS)
# ==========================================
output "rds_endpoint" {
  description = "DB 접속 주소 (Writer)"
  value       = module.rds.endpoint
}

output "rds_reader_endpoint" {
  description = "DB 읽기 전용 주소 (Reader)"
  value       = module.rds.reader_endpoint
}

# ==========================================
# 5. 💻 서버 (Bastion EC2)
# ==========================================
output "bastion_instance_id" {
  description = "베스천 인스턴스 ID (접속용)"
  value       = module.bastion.instance_id
}

output "bastion_public_ip" {
  description = "베스천 공인 IP"
  value       = module.bastion.public_ip
}

# 6. EKS & EFS 정보 (팀원 요청 사항)
# ==========================================

output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS 접속 주소 (Endpoint)"
  value       = module.eks.cluster_endpoint
}

# 팀원이 가장 중요하게 요청한 EFS ID
output "efs_id" {
  description = "EFS 파일 시스템 ID (fs-xxxx)"
  value       = module.efs.id
}

# (참고) EKS 모듈의 outputs.tf에 아래 값들이 정의되어 있어야 에러가 안 납니다!
# output "cluster_iam_role_arn" {
#   value = module.eks.cluster_iam_role_arn
# }


# 요청 사항 (Role ARN 정보)
output "cluster_role_arn" {
  description = "EKS Cluster Role ARN"
  value       = module.eks.cluster_role_arn
}

#output "node_role_arn" {
#  description = "EKS Node Role ARN"
#  value       = module.eks.node_role_arn
#}
# pbs_project/outputs.tf 안에 추가

output "waf_arn" {
  description = "WAF WebACL ARN (Give this to Ingress Team)"
  value       = module.waf.web_acl_arn
}
# ==========================================
# 7. 📦 컨테이너 저장소 (ECR) - CI/CD용
# ==========================================
/*
# GitHub Actions가 이미지를 올릴 때 이 주소가 꼭 필요합니다.
output "ecr_repository_url" {
  description = "ECR 저장소 URL (GitHub Actions에서 사용)"
  value       = aws_ecr_repository.app_repo.repository_url
}
*/
# ==========================================
# 8. 🔒 인증서 (ACM) - Ingress용
# ==========================================
# 나중에 Ingress(대문) 만들 때 "이 인증서 써라"고 알려줘야 합니다.
output "acm_certificate_arn" {
  description = "ACM 인증서 ARN (Ingress에 설정 필요)"
  value       = module.route53_acm.acm_certificate_arn
}

# [선우님 요청] ECR 주소 출력
output "ai_engine_repo_url" {
  value = module.ecr.ai_engine_repo_url
}

output "hybrid_service_repo_url" {
  value = module.ecr.hybrid_service_repo_url
}
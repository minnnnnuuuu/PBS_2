# ==========================================
# 1. 🌐 네트워크 (VPC)
# ==========================================
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

# ==========================================
# 2. 🛡️ 보안 그룹 (Security Group)
# ==========================================
output "bastion_sg_id" {
  value = module.sg.bastion_sg_id
}

output "rds_sg_id" {
  value = module.sg.rds_sg_id
}

# ==========================================
# 4. 🗄️ 데이터베이스 (RDS)
# ==========================================
output "rds_endpoint" {
  value = module.rds.endpoint
}

# ==========================================
# 6. 🚀 EKS & EFS 정보
# ==========================================
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "efs_id" {
  value = module.efs.id
}

# ==========================================
# 7. 📦 컨테이너 저장소 (ECR)
# ==========================================
# [중요] 모듈이 아니라 리소스 이름을 직접 써야 에러가 안 납니다!
output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = aws_ecr_repository.app_repo.repository_url
}

# ==========================================
# 8. 🔒 인증서 (ACM)
# ==========================================
output "acm_certificate_arn" {
  description = "ACM 인증서 ARN"
  value       = module.route53_acm.acm_certificate_arn
}

# WAF 정보
output "waf_arn" {
  value = module.waf.web_acl_arn
}
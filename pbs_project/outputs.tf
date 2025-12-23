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
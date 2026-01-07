# 파일 위치: pbs_project/modules/vpc/outputs.tf

output "vpc_id" {
  description = "생성된 VPC의 ID"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "Public Subnet ID 목록"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "Private App Subnet ID 목록 (EKS용)"
  value       = module.vpc.private_subnets
}

output "database_subnets" {
  description = "Private Data Subnet ID 목록 (RDS용)"
  value       = module.vpc.database_subnets
}

output "database_subnet_group" {
  description = "RDS 서브넷 그룹 이름"
  value       = module.vpc.database_subnet_group
}
# [추가] VPN 모듈 등에서 라우팅 테이블을 참조하기 위해 내보냅니다.
output "private_route_table_ids" {
  description = "IDs of the private route tables"
  # value       = aws_route_table.private[*].id
  value       = module.vpc.private_route_table_ids
}